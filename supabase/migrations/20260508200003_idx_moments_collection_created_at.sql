CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_moments_collection_created_at
  ON public.in_process_moments (collection, created_at);
