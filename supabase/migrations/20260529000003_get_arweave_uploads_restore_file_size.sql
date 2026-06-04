-- get_arweave_uploads: restore file_size_bytes and size sort support
-- (was accidentally dropped in 20260528000001 during the wallet join refactor).
DROP FUNCTION if EXISTS public.get_arweave_uploads (TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_arweave_uploads (
  p_artist TEXT DEFAULT NULL,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_sort_by TEXT DEFAULT 'usdc_cost',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  winc_cost TEXT,
  usdc_cost NUMERIC,
  file_size_bytes BIGINT,
  artist_username TEXT,
  artist_address TEXT,
  total_count BIGINT,
  total_usdc_cost NUMERIC
) language sql stable AS $$
  WITH filtered AS (
    SELECT
      u.artist_address,
      a.username AS artist_username,
      u.winc_cost,
      u.usdc_cost,
      u.file_size_bytes
    FROM in_process_arweave_uploads u
    LEFT JOIN in_process_wallets w ON w.address = u.artist_address
    LEFT JOIN in_process_artists a ON a.id = w.artist
    WHERE
      (p_artist IS NULL OR
        CASE
          WHEN p_artist ~ '^0x[0-9a-fA-F]{40}$' THEN u.artist_address = lower(p_artist)
          ELSE a.username ILIKE p_artist
        END)
      AND (p_from IS NULL OR u.created_at >= p_from)
  ),
  grouped AS (
    SELECT
      f.artist_address,
      f.artist_username,
      COALESCE(
        SUM(COALESCE(NULLIF(trim(f.winc_cost), '')::NUMERIC, 0)),
        0
      ) AS winc_sum,
      COALESCE(SUM(f.usdc_cost), 0) AS usdc_sum,
      COALESCE(SUM(f.file_size_bytes), 0)::BIGINT AS bytes_sum
    FROM filtered f
    GROUP BY f.artist_address, f.artist_username
  ),
  with_totals AS (
    SELECT
      g.artist_address,
      g.artist_username,
      g.winc_sum,
      g.usdc_sum,
      g.bytes_sum,
      COUNT(*) OVER ()::BIGINT AS total_count,
      COALESCE(SUM(g.usdc_sum) OVER (), 0) AS total_usdc_cost
    FROM grouped g
  )
  SELECT
    ROUND(w.winc_sum)::BIGINT::TEXT,
    w.usdc_sum,
    w.bytes_sum,
    w.artist_username,
    w.artist_address,
    w.total_count,
    w.total_usdc_cost
  FROM with_totals w
  ORDER BY
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'asc' THEN w.usdc_sum END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'desc' THEN w.usdc_sum END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'asc' THEN w.winc_sum END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'desc' THEN w.winc_sum END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'asc' THEN w.bytes_sum::NUMERIC END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'desc' THEN w.bytes_sum::NUMERIC END DESC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size') AND p_sort_order = 'asc' THEN w.usdc_sum END ASC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size') AND p_sort_order = 'desc' THEN w.usdc_sum END DESC NULLS LAST
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;
