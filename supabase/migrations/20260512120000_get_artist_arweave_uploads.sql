DROP FUNCTION if EXISTS public.get_artist_arweave_uploads (TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_artist_arweave_uploads (
  p_artist TEXT DEFAULT NULL,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_sort_by TEXT DEFAULT 'created_at',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  id UUID,
  arweave_uri TEXT,
  winc_cost TEXT,
  usdc_cost NUMERIC,
  file_size_bytes BIGINT,
  content_type TEXT,
  created_at TIMESTAMPTZ,
  total_count BIGINT
) language sql stable AS $$
  SELECT
    u.id,
    u.arweave_uri,
    u.winc_cost,
    u.usdc_cost,
    u.file_size_bytes,
    u.content_type,
    u.created_at,
    COUNT(*) OVER ()::BIGINT
  FROM in_process_arweave_uploads u
  JOIN in_process_artists a ON a.address = u.artist_address
  WHERE
    (p_artist IS NULL OR
      CASE
        WHEN p_artist ~ '^0x[0-9a-fA-F]{40}$' THEN u.artist_address = lower(p_artist)
        ELSE lower(trim(a.username)) = lower(trim(p_artist))
      END)
    AND (p_from IS NULL OR u.created_at >= p_from)
  ORDER BY
    CASE p_sort_by
      WHEN 'usdc_cost' THEN u.usdc_cost
      WHEN 'winc_cost' THEN COALESCE(NULLIF(trim(u.winc_cost), '')::NUMERIC, 0)
      WHEN 'size'      THEN u.file_size_bytes::NUMERIC
      ELSE             EXTRACT(EPOCH FROM u.created_at)
    END * CASE p_sort_order WHEN 'asc' THEN 1 ELSE -1 END NULLS LAST
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;
