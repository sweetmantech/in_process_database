CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_metadata_content_mime_trgm ON public.in_process_metadata USING gin (LOWER((content - > > 'mime')) gin_trgm_ops);
