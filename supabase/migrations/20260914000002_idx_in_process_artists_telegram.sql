CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_artists_telegram ON public.in_process_artists (telegram) WHERE telegram IS NOT NULL AND telegram <> '';
