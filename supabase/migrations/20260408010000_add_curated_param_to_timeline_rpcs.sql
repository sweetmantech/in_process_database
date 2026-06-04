-- Add p_curated boolean param to all three timeline RPC functions.
-- curated = false (default): return all moments regardless of artist username
-- curated = true: return only moments where artist has a non-empty username (previous behaviour)
-- ── get_in_process_timeline ──────────────────────────────────────────────────
DROP FUNCTION if EXISTS public.get_in_process_timeline (
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT
);

CREATE OR REPLACE FUNCTION public.get_in_process_timeline (
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT 8453,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
BEGIN
  WITH
  filtered_ids AS (
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND moment_is_visible(m.collection, m.token_id, p_hidden)
      AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
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

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;

-- ── get_artist_timeline ──────────────────────────────────────────────────────
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

CREATE OR REPLACE FUNCTION public.get_artist_timeline (
  p_artist TEXT,
  p_type TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT 8453,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit      int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page      int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val        int := (clamped_page - 1) * capped_limit;
  v_moments         json;
  v_total_count     int;
  v_artist_address  text;
BEGIN
  SELECT address INTO v_artist_address
  FROM in_process_artists
  WHERE address = LOWER(p_artist)
     OR username ILIKE p_artist
  LIMIT 1;

  IF v_artist_address IS NULL THEN
    RETURN build_timeline_result(NULL, 0, capped_limit, clamped_page);
  END IF;

  WITH
  filtered_ids AS (
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
      AND (
        (
          (p_type IS NULL OR p_type = 'default')
          AND c.creator = v_artist_address
          AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, c.creator) = false)
        )
        OR
        (
          (p_type IS NULL OR p_type = 'mutual')
          AND c.creator != v_artist_address
          AND EXISTS (
            SELECT 1 FROM in_process_admins adm_check
            WHERE adm_check.collection = m.collection
              AND (adm_check.token_id = m.token_id OR adm_check.token_id = 0)
              AND adm_check.artist_address = v_artist_address
          )
          AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, v_artist_address) = false)
        )
      )
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

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;

-- ── get_collection_timeline ──────────────────────────────────────────────────
DROP FUNCTION if EXISTS public.get_collection_timeline (
  TEXT,
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  TEXT
);

CREATE OR REPLACE FUNCTION public.get_collection_timeline (
  p_collection TEXT,
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT 8453,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
BEGIN
  WITH
  filtered_ids AS (
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      c.address = LOWER(p_collection)
      AND (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_artist IS NULL OR da.username ILIKE p_artist OR da.address = LOWER(p_artist))
      AND moment_is_visible(m.collection, m.token_id, p_hidden)
      AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
  ),
  total AS (SELECT COUNT(*) AS cnt FROM filtered_ids),
  paged_ids AS (
    SELECT id FROM filtered_ids
    ORDER BY created_at DESC, token_id DESC
    LIMIT capped_limit OFFSET offset_val
  ),
  moment_data AS (
    SELECT
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

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;
