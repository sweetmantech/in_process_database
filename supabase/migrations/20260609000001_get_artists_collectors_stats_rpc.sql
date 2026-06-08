CREATE OR REPLACE FUNCTION public.get_artists_collectors_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'total_created_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  address TEXT,
  username TEXT,
  total_created_count BIGINT,
  total_collected_count BIGINT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT := LOWER(COALESCE(p_sort_by, 'total_created_count'));
  v_sort_order TEXT := LOWER(COALESCE(p_sort_order, 'desc'));
BEGIN
  IF v_sort_by NOT IN ('total_created_count', 'total_collected_count') THEN
    v_sort_by := 'total_created_count';
  END IF;

  IF v_sort_order NOT IN ('asc', 'desc') THEN
    v_sort_order := 'desc';
  END IF;

  RETURN QUERY
  WITH artist_moments AS MATERIALIZED (
    -- get_active_artists_stats filter: moments created in period
    SELECT
      c.creator AS artist_address,
      m.id      AS moment_id
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND moment_matches_period(m.created_at, p_period)
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
  created_counts AS (
    SELECT
      artist_address,
      COUNT(*) AS created_count
    FROM artist_moments
    GROUP BY artist_address
  ),
  collected_counts AS (
    -- artist is t.recipient in paid transfers (they collected others' work)
    SELECT
      t.recipient AS artist_address,
      COUNT(*)    AS collected_count
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w ON w.address = t.recipient
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND moment_matches_period(t.transferred_at, p_period)
    GROUP BY t.recipient
  ),
  stats AS (
    SELECT
      w.address,
      a.username,
      cc.created_count   AS total_created_count,
      col.collected_count AS total_collected_count
    FROM public.in_process_wallets w
    INNER JOIN public.in_process_artists a   ON a.id = w.artist
    INNER JOIN created_counts cc             ON cc.artist_address  = w.address
    INNER JOIN collected_counts col          ON col.artist_address = w.address
    WHERE a.username IS NOT NULL
      AND a.username != ''
  ),
  paged AS (
    SELECT
      s.address,
      s.username,
      s.total_created_count,
      s.total_collected_count,
      COUNT(*) OVER () AS total_count
    FROM stats s
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN
        CASE v_sort_by
          WHEN 'total_created_count'   THEN s.total_created_count
          WHEN 'total_collected_count' THEN s.total_collected_count
        END
      END ASC NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN
        CASE v_sort_by
          WHEN 'total_created_count'   THEN s.total_created_count
          WHEN 'total_collected_count' THEN s.total_collected_count
        END
      END DESC NULLS LAST,
      s.address ASC
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT
    p.address,
    p.username,
    p.total_created_count,
    p.total_collected_count,
    p.total_count
  FROM paged p
  ORDER BY
    CASE WHEN v_sort_order = 'asc' THEN
      CASE v_sort_by
        WHEN 'total_created_count'   THEN p.total_created_count
        WHEN 'total_collected_count' THEN p.total_collected_count
      END
    END ASC NULLS LAST,
    CASE WHEN v_sort_order = 'desc' THEN
      CASE v_sort_by
        WHEN 'total_created_count'   THEN p.total_created_count
        WHEN 'total_collected_count' THEN p.total_collected_count
      END
    END DESC NULLS LAST,
    p.address ASC;
END;
$$;
