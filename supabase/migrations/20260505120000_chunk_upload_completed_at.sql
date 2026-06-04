-- Track completed uploads for monthly quota enforcement.
-- Sessions are now retained with status='done' instead of being deleted on success.
ALTER TABLE in_process_chunk_upload_sessions
ADD COLUMN completed_at TIMESTAMPTZ NULL;

CREATE INDEX in_process_chunk_upload_sessions_artist_done_idx ON in_process_chunk_upload_sessions (artist_address, completed_at)
WHERE
  status = 'done';
