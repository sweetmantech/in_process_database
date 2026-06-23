-- Rewrite hidden-related RPCs to use in_process_hidden table.
-- Depends on: 20260624000001 (wallet → artist in in_process_hidden)
--
-- Improvements:
-- - get_creator_hidden, moment_is_visible eliminated (inlined as simple NOT EXISTS)
-- - hidden check: O(1) via in_process_hidden(moment, artist) unique index
-- - idx_in_process_admins_hidden_moment_lookup dropped (was created solely for old moment_is_visible)
-- - build_moment_json loses creator_hidden param; hidden inlined directly
-- ── 1. Drop partial index created for old moment_is_visible ──────────────────
DROP INDEX if EXISTS public.idx_in_process_admins_hidden_moment_lookup;

-- ── 2. Drop obsolete functions ────────────────────────────────────────────────
DROP FUNCTION if EXISTS public.get_creator_hidden (UUID, NUMERIC, TEXT);

DROP FUNCTION if EXISTS public.moment_is_visible (UUID, NUMERIC, BOOLEAN);

-- ── 3. get_moment_admins_json: address array only (hidden field removed) ──────
CREATE OR REPLACE FUNCTION public.get_moment_admins_json (p_collection UUID, p_token_id NUMERIC) returns JSON language sql stable AS $$
  SELECT COALESCE(
    (SELECT json_agg(artist_address ORDER BY artist_address)
     FROM (
       SELECT DISTINCT ON (adm.artist_address) adm.artist_address
       FROM in_process_admins adm
       WHERE adm.collection = p_collection
         AND (adm.token_id = p_token_id OR adm.token_id = 0)
         AND adm.artist_address IS NOT NULL
       ORDER BY adm.artist_address,
         CASE WHEN adm.token_id = p_token_id THEN 0 ELSE 1 END
     ) sub),
    '[]'::json
  )
$$;

-- ── 4. build_moment_json: remove creator_hidden param, inline hidden ───────────
DROP FUNCTION if EXISTS public.build_moment_json (
  TEXT,
  NUMERIC,
  NUMERIC,
  TEXT,
  UUID,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN,
  UUID,
  JSON,
  TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION public.build_moment_json (
  p_address TEXT,
  p_token_id NUMERIC,
  p_chain_id NUMERIC,
  p_protocol TEXT,
  p_id UUID,
  p_uri TEXT,
  p_creator TEXT,
  p_creator_username TEXT,
  p_collection UUID,
  p_metadata JSON,
  p_created_at TIMESTAMPTZ
) returns JSON language sql stable AS $$
  SELECT json_build_object(
    'address',        p_address,
    'token_id',       p_token_id::text,
    'chain_id',       p_chain_id,
    'protocol',       p_protocol,
    'id',             p_id,
    'uri',            p_uri,
    'creator',        json_build_object('address', p_creator, 'username', p_creator_username),
    'admins',         COALESCE(get_moment_admins_json(p_collection, p_token_id), '[]'::json),
    'hidden',         COALESCE(
                        (SELECT json_agg(h.artist::text ORDER BY h.artist::text)
                         FROM in_process_hidden h WHERE h.moment = p_id),
                        '[]'::json
                      ),
    'created_at',     p_created_at,
    'metadata',       p_metadata
  )
$$;

-- ── 5. get_in_process_timeline ────────────────────────────────────────────────
-- Curated branches: curated_addresses now also selects w.artist so the hidden
-- check can use ca.artist directly without an extra wallet join.
-- Non-curated branches: LEFT JOIN in_process_wallets w_creator added to
-- filtered_ids so w_creator.artist is available for the NOT EXISTS check.
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

  -- ── Branch 1: curated + mime ─────────────────────────────────────────────
  IF p_curated AND p_mime IS NOT NULL THEN
    WITH
    curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    ),
    filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM curated_addresses ca
      INNER JOIN in_process_collections c ON c.creator = ca.address
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      INNER JOIN in_process_moments m ON m.collection = c.id
      INNER JOIN in_process_metadata meta ON meta.moment = m.id
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = ca.artist
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
          md.collection, md.metadata::json, md.created_at
        )
        ORDER BY md.created_at DESC, md.token_id DESC
      )
    INTO v_total_count, v_moments
    FROM moment_data md;

  -- ── Branch 2: curated + no-mime ──────────────────────────────────────────
  ELSIF p_curated THEN
    WITH
    curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    ),
    filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM curated_addresses ca
      INNER JOIN in_process_collections c ON c.creator = ca.address
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      INNER JOIN in_process_moments m ON m.collection = c.id
      WHERE
        moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = ca.artist
        ))
        AND NOT EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.external_url LIKE '%/collect/base:%/%'
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
          md.collection, md.metadata::json, md.created_at
        )
        ORDER BY md.created_at DESC, md.token_id DESC
      )
    INTO v_total_count, v_moments
    FROM moment_data md;

  -- ── Branch 3: non-curated + mime ─────────────────────────────────────────
  ELSIF p_mime IS NOT NULL THEN
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_metadata meta
      INNER JOIN in_process_moments m ON m.id = meta.moment
      INNER JOIN in_process_collections c ON m.collection = c.id
      LEFT JOIN in_process_wallets w_creator ON w_creator.address = c.creator
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_creator.artist
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
          md.collection, md.metadata::json, md.created_at
        )
        ORDER BY md.created_at DESC, md.token_id DESC
      )
    INTO v_total_count, v_moments
    FROM moment_data md;

  -- ── Branch 4: non-curated + no-mime ──────────────────────────────────────
  ELSE
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_moments m
      INNER JOIN in_process_collections c ON m.collection = c.id
      LEFT JOIN in_process_wallets w_creator ON w_creator.address = c.creator
      WHERE
        (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_creator.artist
        ))
        AND NOT EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.external_url LIKE '%/collect/base:%/%'
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
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

-- ── 6. get_artist_timeline ────────────────────────────────────────────────────
-- v_artist_uuid (resolved at function top) used directly in NOT EXISTS check —
-- no wallet join needed since artist UUID is already known.
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = v_artist_uuid
        ))
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = v_artist_uuid
        ))
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = v_artist_uuid
        ))
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))
        AND NOT EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.external_url LIKE '%/collect/base:%/%'
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = v_artist_uuid
        ))
        AND (NOT p_curated OR EXISTS (
          SELECT 1 FROM in_process_wallets wcr
          JOIN in_process_artists acr ON acr.id = wcr.artist
          WHERE wcr.address = c.creator AND acr.username IS NOT NULL AND acr.username != ''
        ))
        AND NOT EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.external_url LIKE '%/collect/base:%/%'
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
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

-- ── 7. get_collection_timeline ────────────────────────────────────────────────
-- filtered_ids already joins in_process_wallets w_c in both branches —
-- w_c.artist used directly for the hidden check.
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_artist IS NULL OR da.username ILIKE p_artist OR w_c.address = LOWER(p_artist))
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_c.artist
        ))
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
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
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND (p_artist IS NULL OR da.username ILIKE p_artist OR w_c.address = LOWER(p_artist))
        AND (p_hidden = true OR NOT EXISTS (
          SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_c.artist
        ))
        AND (NOT p_curated OR (da.username IS NOT NULL AND da.username != ''))
        AND NOT EXISTS (
          SELECT 1 FROM in_process_metadata meta2
          WHERE meta2.moment = m.id
            AND meta2.external_url LIKE '%/collect/base:%/%'
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
        m.id, m.collection, m.token_id, m.uri,
        CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
             THEN to_timestamp(s.sale_start::double precision)
             ELSE m.created_at
        END             AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username     AS creator_username,
        to_jsonb(meta)  AS metadata
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
          md.creator, md.creator_username,
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
