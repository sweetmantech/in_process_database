CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_moments_collection_id
  ON public.in_process_moments (collection, id);
