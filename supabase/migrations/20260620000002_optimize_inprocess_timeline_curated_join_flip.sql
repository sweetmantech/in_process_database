-- get_in_process_timeline: flip join order for curated=true branches.
-- Before: 262K moments → collections → wallets → artists (filter at end)
-- After:  3.3K curated artists → wallets → collections → 31K moments
-- Splits into 4 IF/ELSIF branches: curated×mime combos.
-- Non-curated branches are unchanged from 20260617000006 except the
-- unused wallets/artists LEFT JOINs are removed from filtered_ids.
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
      SELECT w.address
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
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
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
        END                                                      AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username                                              AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator) AS creator_hidden,
        to_jsonb(meta)                                           AS metadata
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

  -- ── Branch 2: curated + no-mime ──────────────────────────────────────────
  ELSIF p_curated THEN
    WITH
    curated_addresses AS MATERIALIZED (
      SELECT w.address
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
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
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
        END                                                      AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username                                              AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator) AS creator_hidden,
        to_jsonb(meta)                                           AS metadata
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

  -- ── Branch 3: non-curated + mime ─────────────────────────────────────────
  ELSIF p_mime IS NOT NULL THEN
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_metadata meta
      INNER JOIN in_process_moments m ON m.id = meta.moment
      INNER JOIN in_process_collections c ON m.collection = c.id
      WHERE meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
        AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
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
        END                                                      AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username                                              AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator) AS creator_hidden,
        to_jsonb(meta)                                           AS metadata
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

  -- ── Branch 4: non-curated + no-mime ──────────────────────────────────────
  ELSE
    WITH filtered_ids AS MATERIALIZED (
      SELECT DISTINCT m.id, m.token_id, m.created_at
      FROM in_process_moments m
      INNER JOIN in_process_collections c ON m.collection = c.id
      WHERE
        (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
        AND moment_matches_period(m.created_at, p_period)
        AND moment_matches_channel(m.id, p_channel)
        AND moment_is_visible(m.collection, m.token_id, p_hidden)
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
        END                                                      AS created_at,
        c.address, c.chain_id, c.protocol, c.creator,
        da.username                                              AS creator_username,
        get_creator_hidden(m.collection, m.token_id, c.creator) AS creator_hidden,
        to_jsonb(meta)                                           AS metadata
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
