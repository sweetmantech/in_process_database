-- When p_chainid IS NULL, return all chains instead of hardcoded IN (1, 8453).
-- This supports chain_id 10 (Optimism) and any future chains without SQL changes.
-- ── get_artist_timeline ───────────────────────────────────────────────────────
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
  capped_limit  int  := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int  := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int  := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
  v_artist_uuid uuid;
BEGIN
  SELECT artist INTO v_artist_uuid
  FROM in_process_wallets
  WHERE address = lower(p_artist);

  IF v_artist_uuid IS NULL THEN
    SELECT id INTO v_artist_uuid
    FROM in_process_artists
    WHERE lower(username) = lower(p_artist)
    LIMIT 1;
  END IF;

  IF p_mime IS NOT NULL THEN
    WITH
    artist_addrs AS MATERIALIZED (
      SELECT address FROM in_process_wallets WHERE artist = v_artist_uuid AND v_artist_uuid IS NOT NULL
      UNION ALL
      SELECT lower(p_artist) WHERE v_artist_uuid IS NULL
    ),
    filtered_ids AS MATERIALIZED (
      SELECT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_collections c ON c.creator = aa.address
      INNER JOIN in_process_moments m ON m.collection = c.id
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'default')
        AND meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, c.creator) = false)
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))

      UNION ALL

      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_admins adm ON adm.artist_address = aa.address
      INNER JOIN in_process_moments m ON m.collection = adm.collection
        AND (m.token_id = adm.token_id OR adm.token_id = 0)
      INNER JOIN in_process_collections c ON m.collection = c.id
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE (p_type IS NULL OR p_type = 'mutual')
        AND NOT EXISTS (SELECT 1 FROM artist_addrs WHERE address = c.creator)
        AND meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, adm.artist_address) = false)
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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
      SELECT address FROM in_process_wallets WHERE artist = v_artist_uuid AND v_artist_uuid IS NOT NULL
      UNION ALL
      SELECT lower(p_artist) WHERE v_artist_uuid IS NULL
    ),
    filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_collections c ON c.creator = aa.address
      INNER JOIN in_process_moments m ON m.collection = c.id
      WHERE (p_type IS NULL OR p_type = 'default')
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, c.creator) = false)
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))
        AND EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.content->>'uri' IS NOT NULL
            AND meta2.content->>'uri' != ''
            AND (meta2.external_url IS NULL OR meta2.external_url NOT LIKE '%/collect/base:%/%')
        )

      UNION ALL

      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM artist_addrs aa
      INNER JOIN in_process_admins adm ON adm.artist_address = aa.address
      INNER JOIN in_process_moments m ON m.collection = adm.collection
        AND (m.token_id = adm.token_id OR adm.token_id = 0)
      INNER JOIN in_process_collections c ON m.collection = c.id
      WHERE (p_type IS NULL OR p_type = 'mutual')
        AND NOT EXISTS (SELECT 1 FROM artist_addrs WHERE address = c.creator)
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR get_creator_hidden(m.collection, m.token_id, adm.artist_address) = false)
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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

-- ── get_in_process_timeline ───────────────────────────────────────────────────
DROP FUNCTION if EXISTS public.get_in_process_timeline (
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN
);

CREATE OR REPLACE FUNCTION public.get_in_process_timeline (
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
      WHERE
        (p_chainid IS NULL OR c.chain_id = p_chainid)
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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

-- ── get_collection_timeline ───────────────────────────────────────────────────
DROP FUNCTION if EXISTS public.get_collection_timeline (
  TEXT,
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN
);

CREATE OR REPLACE FUNCTION public.get_collection_timeline (
  p_collection TEXT,
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT NULL,
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
  IF p_mime IS NOT NULL THEN
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_metadata meta
      INNER JOIN in_process_moments m ON m.id = meta.moment
      INNER JOIN in_process_collections c ON m.collection = c.id
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND c.address = LOWER(p_collection)
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_artist IS NULL OR da.username ILIKE p_artist OR w_c.address = LOWER(p_artist))
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
      WHERE
        c.address = LOWER(p_collection)
        AND (p_chainid IS NULL OR c.chain_id = p_chainid)
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_artist IS NULL OR da.username ILIKE p_artist OR w_c.address = LOWER(p_artist))
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
      LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
      LEFT JOIN in_process_artists da ON da.id = w_c.artist
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
