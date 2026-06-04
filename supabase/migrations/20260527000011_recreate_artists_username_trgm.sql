CREATE INDEX CONCURRENTLY idx_in_process_artists_username_trgm ON in_process_artists USING gin (username gin_trgm_ops);
