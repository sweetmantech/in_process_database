CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moments_collection_token_id ON public.in_process_moments (collection, token_id);
