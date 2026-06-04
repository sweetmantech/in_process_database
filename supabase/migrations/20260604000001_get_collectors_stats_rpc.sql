CREATE OR REPLACE FUNCTION public.get_collectors_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'collected_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  collector TEXT,
  username TEXT,
  collected_count BIGINT,
  eth_spent TEXT,
  usdc_spent TEXT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT := LOWER(COALESCE(p_sort_by, 'collected_count'));
  v_sort_order TEXT := LOWER(COALESCE(p_sort_order, 'desc'));
  v_usdc_addr  TEXT := '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';
  v_eth_addr   TEXT := '0x0000000000000000000000000000000000000000';
BEGIN
  IF v_sort_by NOT IN ('collected_count', 'eth_spent', 'usdc_spent') THEN
    v_sort_by := 'collected_count';
  END IF;

  IF v_sort_order NOT IN ('asc', 'desc') THEN
    v_sort_order := 'desc';
  END IF;

  RETURN QUERY
  WITH paid_transfers AS MATERIALIZED (
    SELECT
      t.recipient,
      t.value,
      t.currency,
      a.id       AS artist_id,
      a.username AS username
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w ON w.address = t.recipient
    INNER JOIN public.in_process_artists a ON a.id = w.artist
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND a.username IS NOT NULL
      AND a.username != ''
      AND moment_matches_period(t.transferred_at, p_period)
      AND (
        p_artist IS NULL
        OR c.creator = LOWER(p_artist)
        OR c.creator IN (
          SELECT w2.address
          FROM public.in_process_wallets w2
          INNER JOIN public.in_process_artists a2 ON a2.id = w2.artist
          WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  stats AS (
    SELECT
      MIN(pt.recipient)                                                                      AS collector,
      pt.username,
      COUNT(*)                                                                               AS collected_count,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_eth_addr), 0)           AS eth_spent,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_usdc_addr), 0)          AS usdc_spent
    FROM paid_transfers pt
    GROUP BY pt.artist_id, pt.username
  ),
  paged AS (
    SELECT
      s.collector,
      s.username,
      s.collected_count,
      s.eth_spent,
      s.usdc_spent,
      COUNT(*) OVER () AS total_count
    FROM stats s
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN
        CASE v_sort_by
          WHEN 'collected_count' THEN s.collected_count::NUMERIC
          WHEN 'eth_spent'       THEN s.eth_spent
          WHEN 'usdc_spent'      THEN s.usdc_spent
        END
      END ASC NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN
        CASE v_sort_by
          WHEN 'collected_count' THEN s.collected_count::NUMERIC
          WHEN 'eth_spent'       THEN s.eth_spent
          WHEN 'usdc_spent'      THEN s.usdc_spent
        END
      END DESC NULLS LAST,
      s.collector ASC
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT
    p.collector,
    p.username,
    p.collected_count,
    TRIM(TRAILING '.' FROM to_char(p.eth_spent,  'FM999999999999990.999999999999999999')),
    TRIM(TRAILING '.' FROM to_char(p.usdc_spent, 'FM999999999999990.999999')),
    p.total_count
  FROM paged p
  ORDER BY
    CASE WHEN v_sort_order = 'asc' THEN
      CASE v_sort_by
        WHEN 'collected_count' THEN p.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN p.eth_spent
        WHEN 'usdc_spent'      THEN p.usdc_spent
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_order = 'desc' THEN
      CASE v_sort_by
        WHEN 'collected_count' THEN p.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN p.eth_spent
        WHEN 'usdc_spent'      THEN p.usdc_spent
      END
    END DESC NULLS LAST,
    p.collector ASC;
END;
$$;
