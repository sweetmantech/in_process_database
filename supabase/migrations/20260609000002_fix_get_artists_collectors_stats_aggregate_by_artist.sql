DROP FUNCTION if EXISTS public.get_artists_collectors_stats (TEXT, INT, INT, TEXT, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_artists_collectors_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'total_created_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  artist_id TEXT,
  username TEXT,
  wallets JSONB,
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
    -- resolve creator wallet → artist UUID so multi-wallet artists aggregate correctly
    SELECT
      w.artist   AS artist_id,
      m.id       AS moment_id
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w     ON w.address = c.creator
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND moment_matches_period(m.created_at, p_period)
      AND (
        p_artist IS NULL
        OR w.artist IN (
          SELECT w2.artist
          FROM public.in_process_wallets w2
          WHERE w2.address = LOWER(p_artist)
        )
        OR w.artist IN (
          SELECT a2.id
          FROM public.in_process_artists a2
          WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  created_counts AS (
    SELECT
      am.artist_id,
      COUNT(*) AS created_count
    FROM artist_moments am
    GROUP BY am.artist_id
  ),
  collected_counts AS (
    -- resolve recipient wallet → artist UUID so multi-wallet artists aggregate correctly
    SELECT
      w.artist   AS artist_id,
      COUNT(*)   AS collected_count
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m     ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w     ON w.address = t.recipient
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND moment_matches_period(t.transferred_at, p_period)
    GROUP BY w.artist
  ),
  artist_wallets AS (
    SELECT
      w.artist AS artist_id,
      JSONB_AGG(
        JSONB_BUILD_OBJECT('address', w.address, 'type', w.type)
        ORDER BY w.address
      ) AS wallets
    FROM public.in_process_wallets w
    GROUP BY w.artist
  ),
  stats AS (
    SELECT
      a.id::TEXT          AS artist_id,
      a.username,
      aw.wallets,
      cc.created_count    AS total_created_count,
      col.collected_count AS total_collected_count
    FROM public.in_process_artists a
    INNER JOIN created_counts   cc  ON cc.artist_id  = a.id
    INNER JOIN collected_counts col ON col.artist_id = a.id
    INNER JOIN artist_wallets   aw  ON aw.artist_id  = a.id
    WHERE a.username IS NOT NULL
      AND a.username != ''
  ),
  with_sort AS (
    SELECT
      s.artist_id,
      s.username,
      s.wallets,
      s.total_created_count,
      s.total_collected_count,
      COUNT(*) OVER () AS total_count,
      CASE v_sort_by
        WHEN 'total_created_count'   THEN s.total_created_count
        WHEN 'total_collected_count' THEN s.total_collected_count
      END AS sort_key
    FROM stats s
  ),
  paged AS (
    SELECT *
    FROM with_sort
    ORDER BY
      CASE WHEN v_sort_order = 'asc'  THEN sort_key END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN sort_key END DESC NULLS LAST,
      artist_id ASC
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT
    p.artist_id,
    p.username,
    p.wallets,
    p.total_created_count,
    p.total_collected_count,
    p.total_count
  FROM paged p
  ORDER BY
    CASE WHEN v_sort_order = 'asc'  THEN p.sort_key END ASC  NULLS LAST,
    CASE WHEN v_sort_order = 'desc' THEN p.sort_key END DESC NULLS LAST,
    p.artist_id ASC;
END;
$$;
