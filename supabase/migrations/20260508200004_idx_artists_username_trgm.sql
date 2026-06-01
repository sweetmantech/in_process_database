CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_artists_username_trgm
  ON public.in_process_artists USING gin (username gin_trgm_ops);
