CREATE OR REPLACE FUNCTION public.timeline_moment_visible (
  p_moment_id UUID,
  p_collection UUID,
  p_chainid NUMERIC,
  p_protocol TEXT,
  p_hidden BOOLEAN,
  p_curated BOOLEAN,
  p_mime TEXT
) returns BOOLEAN language sql stable AS $function$
  SELECT EXISTS (
    SELECT 1
    FROM in_process_collections c
    LEFT JOIN in_process_wallets w ON w.address = c.creator
    LEFT JOIN in_process_artists a ON a.id = w.artist
    WHERE c.id = p_collection
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
      AND (NOT p_curated OR (a.username IS NOT NULL AND a.username != ''))
      AND (p_hidden OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden h WHERE h.moment = p_moment_id AND h.artist = w.artist
      ))
  )
  AND CASE
    WHEN p_mime IS NULL THEN NOT EXISTS (
      SELECT 1 FROM in_process_metadata meta
      WHERE meta.moment = p_moment_id
        AND meta.external_url LIKE '%/collect/base:%/%'
    )
    ELSE EXISTS (
      SELECT 1 FROM in_process_metadata meta
      WHERE meta.moment = p_moment_id
        AND meta.content->>'mime' LIKE p_mime
        AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
        AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
    )
  END
$function$;

CREATE OR REPLACE FUNCTION public.timeline_filtered_ids (
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE,
  p_protocol TEXT DEFAULT NULL
) returns TABLE (
  moment_id UUID,
  moment_token_id NUMERIC,
  moment_created_at TIMESTAMPTZ
) language plpgsql stable AS $function$
BEGIN
  IF p_curated AND p_mime IS NOT NULL THEN
    RETURN QUERY
    WITH curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    )
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM curated_addresses ca
    INNER JOIN in_process_collections c ON c.creator = ca.address
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
    INNER JOIN in_process_moments m ON m.collection = c.id
    INNER JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE meta.content->>'mime' LIKE p_mime
      AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
      AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = ca.artist
      ));

  ELSIF p_curated THEN
    RETURN QUERY
    WITH curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    )
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM curated_addresses ca
    INNER JOIN in_process_collections c ON c.creator = ca.address
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
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
      );

  ELSIF p_mime IS NOT NULL THEN
    RETURN QUERY
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_metadata meta
    INNER JOIN in_process_moments m ON m.id = meta.moment
    INNER JOIN in_process_collections c ON m.collection = c.id
    LEFT JOIN in_process_wallets w_creator ON w_creator.address = c.creator
    WHERE meta.content->>'mime' LIKE p_mime
      AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
      AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_creator.artist
      ));

  ELSE
    RETURN QUERY
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    LEFT JOIN in_process_wallets w_creator ON w_creator.address = c.creator
    WHERE
      (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_creator.artist
      ))
      AND NOT EXISTS (
        SELECT 1 FROM in_process_metadata meta2
        WHERE meta2.moment = m.id
          AND meta2.external_url LIKE '%/collect/base:%/%'
      );
  END IF;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_in_process_timeline_count (
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE,
  p_protocol TEXT DEFAULT NULL
) returns INTEGER language sql stable AS $function$
  SELECT COUNT(*)::int
  FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
$function$;

DROP FUNCTION if EXISTS public.get_in_process_timeline (
  INTEGER,
  INTEGER,
  NUMERIC,
  BOOLEAN,
  TEXT,
  TEXT,
  TEXT,
  BOOLEAN,
  TEXT
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
  p_total_count INTEGER DEFAULT NULL
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
      SELECT moment_id, moment_created_at, moment_token_id
      FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
    )
    SELECT
      (SELECT COUNT(*) FROM filtered),
      (
        SELECT array_agg(f.moment_id ORDER BY f.moment_created_at DESC, f.moment_token_id DESC, f.moment_id DESC)
        FROM (
          SELECT moment_id, moment_created_at, moment_token_id
          FROM filtered
          ORDER BY moment_created_at DESC, moment_token_id DESC, moment_id DESC
          LIMIT capped_limit OFFSET offset_val
        ) f
      )
    INTO v_total_count, v_ids;
  ELSIF p_total_count > 0
     AND (offset_val + capped_limit) * v_table_rows / p_total_count <= 3000 THEN
    SELECT array_agg(p.id ORDER BY p.created_at DESC, p.token_id DESC, p.id DESC)
    INTO v_ids
    FROM (
      SELECT m.id, m.created_at, m.token_id
      FROM in_process_moments m
      WHERE m.created_at >= v_since
        AND moment_matches_period(m.created_at, p_period)
        AND (p_channel IS NULL OR m.channel = p_channel OR (p_channel = 'web' AND m.channel IS NULL))
        AND timeline_moment_visible(m.id, m.collection, p_chainid, p_protocol, p_hidden, p_curated, p_mime)
      ORDER BY m.created_at DESC, m.token_id DESC, m.id DESC
      LIMIT capped_limit OFFSET offset_val
    ) p;
  ELSE
    SELECT array_agg(f.moment_id ORDER BY f.moment_created_at DESC, f.moment_token_id DESC, f.moment_id DESC)
    INTO v_ids
    FROM (
      SELECT moment_id, moment_created_at, moment_token_id
      FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
      ORDER BY moment_created_at DESC, moment_token_id DESC, moment_id DESC
      LIMIT capped_limit OFFSET offset_val
    ) f;
  END IF;

  WITH moment_data AS (
    SELECT DISTINCT
      m.id, m.collection, m.token_id, m.uri,
      CASE WHEN s.id IS NOT NULL AND s.sale_start <> 0
           THEN to_timestamp(s.sale_start::double precision)
           ELSE m.created_at
      END                                                      AS created_at,
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
