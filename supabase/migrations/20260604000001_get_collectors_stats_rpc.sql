CREATE FUNCTION public.get_collectors_stats (
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
  eth_spent NUMERIC,
  usdc_spent NUMERIC,
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
      t.currency
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND moment_matches_period(t.transferred_at, p_period)
      AND (
        p_artist IS NULL
        OR c.creator = LOWER(p_artist)
        OR c.creator IN (
          SELECT w.address
          FROM public.in_process_wallets w
          INNER JOIN public.in_process_artists a ON a.id = w.artist
          WHERE a.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  stats AS (
    SELECT
      pt.recipient                                                                                     AS collector,
      COUNT(*)                                                                                         AS collected_count,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_eth_addr), 0) / 1e18             AS eth_spent,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_usdc_addr), 0) / 1e6             AS usdc_spent
    FROM paid_transfers pt
    GROUP BY pt.recipient
  ),
  paged AS (
    SELECT
      s.collector,
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
      END DESC NULLS LAST
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT
    p.collector,
    a.username,
    p.collected_count,
    p.eth_spent,
    p.usdc_spent,
    p.total_count
  FROM paged p
  LEFT JOIN public.in_process_wallets w ON w.address = p.collector
  LEFT JOIN public.in_process_artists a ON a.id = w.artist
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
    END DESC NULLS LAST;
END;
$$;
