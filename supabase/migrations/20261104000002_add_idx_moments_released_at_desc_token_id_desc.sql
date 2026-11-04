CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moments_released_at_desc_token_id_desc ON public.in_process_moments (released_at DESC, token_id DESC);
