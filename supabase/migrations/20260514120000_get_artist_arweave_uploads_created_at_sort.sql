-- get_artist_arweave_uploads: explicit created_at sort (and stable ORDER BY matching get_arweave_uploads style).

DROP FUNCTION IF EXISTS public.get_artist_arweave_uploads(text, timestamptz, integer, integer, text, text);

CREATE OR REPLACE FUNCTION public.get_artist_arweave_uploads(
  p_artist     TEXT DEFAULT NULL,
  p_from       TIMESTAMPTZ DEFAULT NULL,
  p_limit      INT DEFAULT 20,
  p_page       INT DEFAULT 1,
  p_sort_by    TEXT DEFAULT 'created_at',
  p_sort_order TEXT DEFAULT 'desc'
)
RETURNS TABLE (
  id              UUID,
  arweave_uri     TEXT,
  winc_cost       TEXT,
  usdc_cost       NUMERIC,
  file_size_bytes BIGINT,
  content_type    TEXT,
  created_at      TIMESTAMPTZ,
  total_count     BIGINT
)
LANGUAGE sql
STABLE
AS $$
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
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'asc' THEN u.usdc_cost END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'desc' THEN u.usdc_cost END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'asc' THEN COALESCE(NULLIF(trim(u.winc_cost), '')::NUMERIC, 0) END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'desc' THEN COALESCE(NULLIF(trim(u.winc_cost), '')::NUMERIC, 0) END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'asc' THEN u.file_size_bytes::NUMERIC END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'desc' THEN u.file_size_bytes::NUMERIC END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN u.created_at END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN u.created_at END DESC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size', 'created_at') AND p_sort_order = 'asc' THEN u.created_at END ASC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size', 'created_at') AND p_sort_order = 'desc' THEN u.created_at END DESC NULLS LAST
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;
