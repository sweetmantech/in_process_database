CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_metadata_content_mime_trgm
  ON public.in_process_metadata
  USING gin (lower((content->>'mime')) gin_trgm_ops);
