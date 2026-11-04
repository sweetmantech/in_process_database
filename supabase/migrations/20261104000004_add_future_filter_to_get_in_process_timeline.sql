DROP FUNCTION if EXISTS public.get_in_process_timeline (
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN,
  TEXT,
  INTEGER
);

CREATE OR REPLACE FUNCTION public.get_in_process_timeline (
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE,
  p_protocol TEXT DEFAULT NULL,
  p_total_count INTEGER DEFAULT NULL,
  p_future BOOLEAN DEFAULT TRUE
) returns JSON language plpgsql
SET
  plan_cache_mode = force_custom_plan AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_since       timestamptz := CASE p_period
                                 WHEN 'day'   THEN NOW() - INTERVAL '1 day'
                                 WHEN 'week'  THEN NOW() - INTERVAL '7 days'
                                 WHEN 'month' THEN NOW() - INTERVAL '30 days'
                                 ELSE '-infinity'::timestamptz
                               END;
  v_until       timestamptz := CASE WHEN p_future THEN 'infinity'::timestamptz ELSE NOW() + INTERVAL '1 year' END;
  v_total_count int := p_total_count;
  v_table_rows  numeric := GREATEST(
                         (SELECT reltuples FROM pg_class WHERE oid = 'public.in_process_moments'::regclass),
                         1
                       );
  v_ids         uuid[];
  v_moments     json;
BEGIN
  IF p_total_count IS NULL THEN
    WITH filtered AS MATERIALIZED (
      SELECT moment_id, moment_released_at, moment_token_id
      FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
    )
    SELECT
      (SELECT COUNT(*) FROM filtered),
      (
        SELECT array_agg(f.moment_id ORDER BY f.moment_released_at DESC, f.moment_token_id DESC, f.moment_id DESC)
        FROM (
          SELECT moment_id, moment_released_at, moment_token_id
          FROM filtered
          WHERE moment_released_at <= v_until
          ORDER BY moment_released_at DESC, moment_token_id DESC, moment_id DESC
          LIMIT capped_limit OFFSET offset_val
        ) f
      )
    INTO v_total_count, v_ids;
  ELSIF p_total_count > 0
     AND (offset_val + capped_limit) * v_table_rows / p_total_count <= 3000 THEN
    SELECT array_agg(p.id ORDER BY p.released_at DESC, p.token_id DESC, p.id DESC)
    INTO v_ids
    FROM (
      SELECT m.id, m.released_at, m.token_id
      FROM in_process_moments m
      WHERE m.created_at >= v_since
        AND m.released_at <= v_until
        AND moment_matches_period(m.created_at, p_period)
        AND (p_channel IS NULL OR m.channel = p_channel OR (p_channel = 'web' AND m.channel IS NULL))
        AND timeline_moment_visible(m.id, m.collection, p_chainid, p_protocol, p_hidden, p_curated, p_mime)
      ORDER BY m.released_at DESC, m.token_id DESC, m.id DESC
      LIMIT capped_limit OFFSET offset_val
    ) p;
  ELSE
    SELECT array_agg(f.moment_id ORDER BY f.moment_released_at DESC, f.moment_token_id DESC, f.moment_id DESC)
    INTO v_ids
    FROM (
      SELECT moment_id, moment_released_at, moment_token_id
      FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
      WHERE moment_released_at <= v_until
      ORDER BY moment_released_at DESC, moment_token_id DESC, moment_id DESC
      LIMIT capped_limit OFFSET offset_val
    ) f;
  END IF;

  WITH moment_data AS (
    SELECT DISTINCT
      m.id, m.collection, m.token_id, m.uri,
      m.released_at                                                      AS created_at,
      c.address, c.chain_id, c.protocol, c.creator, c.name     AS collection_name,
      da.username                                              AS creator_username,
      to_jsonb(meta)                                           AS metadata,
      CASE WHEN s.id IS NOT NULL THEN
        jsonb_build_object(
          'pricePerToken',       s.price_per_token::text,
          'saleStart',           s.sale_start,
          'saleEnd',             s.sale_end,
          'maxTokensPerAddress', s.max_tokens_per_address,
          'fundsRecipient',      s.funds_recipient,
          'type',                CASE WHEN s.currency = '0x0000000000000000000000000000000000000000'
                                      THEN 'fixedPrice' ELSE 'erc20Mint' END
        )
      END                                                      AS sale
    FROM unnest(v_ids) AS pi(id)
    INNER JOIN in_process_moments m ON m.id = pi.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
    LEFT JOIN in_process_artists da ON da.id = w_c.artist
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    LEFT JOIN in_process_sales s ON s.moment = m.id
  )
  SELECT
    json_agg(
      build_moment_json(
        md.address, md.token_id, md.chain_id, md.protocol::text, md.id, md.uri,
        md.creator, md.creator_username,
        md.collection, md.metadata::json, md.created_at,
        md.sale::json, md.collection_name
      )
      ORDER BY md.created_at DESC, md.token_id DESC
    )
  INTO v_moments
  FROM moment_data md;

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;
