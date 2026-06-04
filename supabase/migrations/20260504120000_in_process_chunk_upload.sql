-- Staged binary chunks for multi-request uploads (max 4 MiB per part enforced in API).
-- Chunk bytes are stored in Vercel Blob; this table only stores the blob URL per part.
CREATE TABLE in_process_chunk_upload_sessions (
  id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
  artist_address TEXT NOT NULL REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE,
  filename TEXT NOT NULL,
  content_type TEXT NOT NULL DEFAULT 'application/octet-stream',
  total_chunks INTEGER NOT NULL CHECK (
    total_chunks > 0
    AND total_chunks <= 139
  ),
  total_size_bytes BIGINT NULL CHECK (
    total_size_bytes IS NULL
    OR (
      total_size_bytes > 0
      AND total_size_bytes <= 555 * 1024 * 1024
    )
  ),
  status TEXT NOT NULL DEFAULT 'open' CHECK (
    status IN ('open', 'completing', 'done', 'failed', 'expired')
  ),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (NOW() + INTERVAL '2 hours')
);

CREATE TABLE in_process_chunk_upload_parts (
  id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
  session_id UUID NOT NULL REFERENCES in_process_chunk_upload_sessions (id) ON DELETE CASCADE,
  chunk_index INTEGER NOT NULL CHECK (
    chunk_index >= 0
    AND chunk_index < 139
  ),
  byte_length INTEGER NOT NULL CHECK (
    byte_length > 0
    AND byte_length <= 4194304
  ),
  blob_url TEXT NOT NULL,
  UNIQUE (session_id, chunk_index)
);

ALTER TABLE in_process_chunk_upload_sessions enable ROW level security;

ALTER TABLE in_process_chunk_upload_parts enable ROW level security;

CREATE INDEX in_process_chunk_upload_sessions_artist_address_idx ON in_process_chunk_upload_sessions (artist_address);

CREATE INDEX in_process_chunk_upload_sessions_expires_idx ON in_process_chunk_upload_sessions (expires_at)
WHERE
  status = 'open';
