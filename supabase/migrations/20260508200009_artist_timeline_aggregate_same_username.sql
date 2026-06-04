-- When multiple in_process_artists rows share the same username (e.g. "cxy"),
-- aggregate all their addresses and return moments for all of them.
-- Also handles address input: resolves address → username → all addresses with that username.
--
-- Base: 20260418100000 (MATERIALIZED filtered_ids, IF/ELSE mime branch, prod chain filter).
-- Drop both the 9-param (without p_curated) and 10-param (with p_curated) signatures
-- so no stale overload remains after this migration.
--
-- Performance: filtered_ids uses explicit JOINs from artist_addrs so the planner can
-- use the c.creator index (nested-loop index scan) instead of a full table scan.
-- Functional index for LOWER(username) exact lookups (Step 1b and artist_addrs CTE).
CREATE INDEX if NOT EXISTS idx_in_process_artists_username_lower ON public.in_process_artists (LOWER(username));

-- Index for mutual branch: JOIN on adm.artist_address = aa.address.
-- Without this, in_process_admins is seq-scanned for every artist lookup.
CREATE INDEX if NOT EXISTS idx_in_process_admins_artist_address ON public.in_process_admins (artist_address);

DROP FUNCTION if EXISTS public.get_artist_timeline (
  TEXT,
  TEXT,
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT
);

DROP FUNCTION if EXISTS public.get_artist_timeline (
  TEXT,
  TEXT,
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN
);

CREATE OR REPLACE FUNCTION public.get_artist_timeline (
  p_artist TEXT,
  p_type TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit         int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page         int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val           int := (clamped_page - 1) * capped_limit;
  v_moments            json;
  v_total_count        int;
  v_resolved_username  text;
  v_artist_found       boolean := false;
BEGIN
  -- Step 1a: try address first (PK lookup, O(1)).
  SELECT username INTO v_resolved_username
  FROM in_process_artists
  WHERE address = LOWER(p_artist);

  IF FOUND THEN
    v_artist_found := true;
  ELSE
    -- Step 1b: try username (functional index on LOWER(username)).
    SELECT username INTO v_resolved_username
    FROM in_process_artists
    WHERE LOWER(username) = LOWER(p_artist)
    LIMIT 1;
    v_artist_found := FOUND;
  END IF;

  IF NOT v_artist_found THEN
    RETURN build_timeline_result(NULL, 0, capped_limit, clamped_page);
  END IF;

  -- Normalize once so artist_addrs CTE needs no LOWER on the right side.
  v_resolved_username := LOWER(v_resolved_username);

  IF p_mime IS NOT NULL THEN
    WITH
    artist_addrs AS MATERIALIZED (
      SELECT a.address FROM in_process_artists a
      WHERE (v_resolved_username IS NOT NULL AND v_resolved_username != '' AND LOWER(a.username) = v_resolved_username)
         OR ((v_resolved_username IS NULL OR v_resolved_username = '') AND a.address = LOWER(p_artist))
    ),
    filtered_ids AS MATERIALIZED (
      -- Default: artist is the creator.
      -- JOIN from artist_addrs so planner uses c.creator index (nested-loop), not full scan.
      SELECT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_collections c ON c.creator = aa.address
      INNER JOIN in_process_moments m ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'default')
        AND meta.content->>'mime' LIKE p_mime
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, c.creator) = false)

      UNION ALL

      -- Mutual: artist is an admin but NOT the creator.
      -- JOIN from artist_addrs → admins so only admin-related moments are scanned.
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_admins adm ON adm.artist_address = aa.address
      INNER JOIN in_process_moments m ON m.collection = adm.collection
        AND (m.token_id = adm.token_id OR adm.token_id = 0)
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'mutual')
        AND NOT EXISTS (SELECT 1 FROM artist_addrs WHERE address = c.creator)
        AND meta.content->>'mime' LIKE p_mime
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, adm.artist_address) = false)
    ),
    total AS (SELECT COUNT(*) AS cnt FROM filtered_ids),
    paged_ids AS (
      SELECT id FROM filtered_ids
      ORDER BY created_at DESC, token_id DESC
      LIMIT capped_limit OFFSET offset_val
    ),
    moment_data AS (
      SELECT DISTINCT
        m.id,
        m.collection,
        m.token_id,
        m.uri,
        m.created_at,
        c.address,
        c.chain_id,
        c.protocol,
        c.creator,
        da.username                                                   AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator)      AS creator_hidden,
        to_jsonb(meta)                                                AS metadata
      FROM paged_ids pi
      INNER JOIN in_process_moments m ON m.id = pi.id
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    )
    SELECT
      (SELECT cnt FROM total),
      json_agg(
        build_moment_json(
          md.address, md.token_id, md.chain_id, md.protocol::text, md.id, md.uri,
          md.creator, md.creator_username, md.creator_hidden,
          md.collection, md.metadata::json, md.created_at
        )
        ORDER BY md.created_at DESC, md.token_id DESC
      )
    INTO v_total_count, v_moments
    FROM moment_data md;
  ELSE
    WITH
    artist_addrs AS MATERIALIZED (
      SELECT a.address FROM in_process_artists a
      WHERE (v_resolved_username IS NOT NULL AND v_resolved_username != '' AND LOWER(a.username) = v_resolved_username)
         OR ((v_resolved_username IS NULL OR v_resolved_username = '') AND a.address = LOWER(p_artist))
    ),
    filtered_ids AS MATERIALIZED (
      -- Default: artist is the creator.
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_collections c ON c.creator = aa.address
      INNER JOIN in_process_moments m ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE (p_type IS NULL OR p_type = 'default')
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, c.creator) = false)

      UNION ALL

      -- Mutual: artist is an admin but NOT the creator.
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_admins adm ON adm.artist_address = aa.address
      INNER JOIN in_process_moments m ON m.collection = adm.collection
        AND (m.token_id = adm.token_id OR adm.token_id = 0)
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE (p_type IS NULL OR p_type = 'mutual')
        AND NOT EXISTS (SELECT 1 FROM artist_addrs WHERE address = c.creator)
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, adm.artist_address) = false)
    ),
    total AS (SELECT COUNT(*) AS cnt FROM filtered_ids),
    paged_ids AS (
      SELECT id FROM filtered_ids
      ORDER BY created_at DESC, token_id DESC
      LIMIT capped_limit OFFSET offset_val
    ),
    moment_data AS (
      SELECT DISTINCT
        m.id,
        m.collection,
        m.token_id,
        m.uri,
        m.created_at,
        c.address,
        c.chain_id,
        c.protocol,
        c.creator,
        da.username                                                   AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator)      AS creator_hidden,
        to_jsonb(meta)                                                AS metadata
      FROM paged_ids pi
      INNER JOIN in_process_moments m ON m.id = pi.id
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    )
    SELECT
      (SELECT cnt FROM total),
      json_agg(
        build_moment_json(
          md.address, md.token_id, md.chain_id, md.protocol::text, md.id, md.uri,
          md.creator, md.creator_username, md.creator_hidden,
          md.collection, md.metadata::json, md.created_at
        )
        ORDER BY md.created_at DESC, md.token_id DESC
      )
    INTO v_total_count, v_moments
    FROM moment_data md;
  END IF;

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;
