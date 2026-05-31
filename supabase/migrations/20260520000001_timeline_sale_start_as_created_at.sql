-- For all 3 timeline RPCs: when a sale exists for a moment AND sale_start != 0,
-- use to_timestamp(sale_start) as created_at instead of m.created_at.
-- If no sale row exists or sale_start = 0, fall back to m.created_at.
-- Change is isolated to the moment_data CTE in each branch of each function.

-- ── get_in_process_timeline ──────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_in_process_timeline(integer, integer, numeric, boolean, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.get_in_process_timeline(
  p_limit   integer DEFAULT 100,
  p_page    integer DEFAULT 1,
  p_chainid numeric DEFAULT NULL,
  p_hidden  boolean DEFAULT false,
  p_mime    text    DEFAULT NULL,
  p_period  text    DEFAULT NULL,
  p_channel text    DEFAULT NULL,
  p_curated boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
BEGIN
  IF p_mime IS NOT NULL THEN
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_metadata meta
      INNER JOIN in_process_moments m ON m.id = meta.moment
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_moments m
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE
        (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.content->>'uri' IS NOT NULL
            AND meta2.content->>'uri' != ''
            AND (meta2.external_url IS NULL OR meta2.external_url NOT LIKE '%/collect/base:%/%')
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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

-- ── get_artist_timeline ──────────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_artist_timeline(text, text, integer, integer, numeric, boolean, text, text, text);
DROP FUNCTION IF EXISTS public.get_artist_timeline(text, text, integer, integer, numeric, boolean, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.get_artist_timeline(
  p_artist  text,
  p_type    text    DEFAULT NULL,
  p_limit   integer DEFAULT 100,
  p_page    integer DEFAULT 1,
  p_chainid numeric DEFAULT NULL,
  p_hidden  boolean DEFAULT false,
  p_mime    text    DEFAULT NULL,
  p_period  text    DEFAULT NULL,
  p_channel text    DEFAULT NULL,
  p_curated boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
AS $function$
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
      SELECT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_collections c ON c.creator = aa.address
      INNER JOIN in_process_moments m ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'default')
        AND meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
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
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'mutual')
        AND NOT EXISTS (SELECT 1 FROM artist_addrs WHERE address = c.creator)
        AND meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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
        AND EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.content->>'uri' IS NOT NULL
            AND meta2.content->>'uri' != ''
            AND (meta2.external_url IS NULL OR meta2.external_url NOT LIKE '%/collect/base:%/%')
        )

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
        AND EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.content->>'uri' IS NOT NULL
            AND meta2.content->>'uri' != ''
            AND (meta2.external_url IS NULL OR meta2.external_url NOT LIKE '%/collect/base:%/%')
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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

-- ── get_collection_timeline ──────────────────────────────────────────────────
DROP FUNCTION IF EXISTS public.get_collection_timeline(text, integer, integer, numeric, boolean, text, text, text, text, boolean);

CREATE OR REPLACE FUNCTION public.get_collection_timeline(
  p_collection text,
  p_limit      integer DEFAULT 100,
  p_page       integer DEFAULT 1,
  p_chainid    numeric DEFAULT NULL,
  p_hidden     boolean DEFAULT false,
  p_mime       text    DEFAULT NULL,
  p_period     text    DEFAULT NULL,
  p_channel    text    DEFAULT NULL,
  p_artist     text    DEFAULT NULL,
  p_curated    boolean DEFAULT false
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
BEGIN
  IF p_mime IS NOT NULL THEN
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_metadata meta
      INNER JOIN in_process_moments m ON m.id = meta.moment
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND c.address = LOWER(p_collection)
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_moments m
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_artists da ON c.creator = da.address
      WHERE
        c.address = LOWER(p_collection)
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_artist IS NULL OR da.username ILIKE p_artist OR da.address = LOWER(p_artist))
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.content->>'uri' IS NOT NULL
            AND meta2.content->>'uri' != ''
            AND (meta2.external_url IS NULL OR meta2.external_url NOT LIKE '%/collect/base:%/%')
        )
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
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END                                                           AS created_at,
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
      LEFT JOIN in_process_sales s ON s.moment = m.id
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
