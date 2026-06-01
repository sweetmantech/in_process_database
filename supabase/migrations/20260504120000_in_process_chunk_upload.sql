-- Staged binary chunks for multi-request uploads (max 4 MiB per part enforced in API).
-- Chunk bytes are stored in Vercel Blob; this table only stores the blob URL per part.

CREATE TABLE in_process_chunk_upload_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  artist_address text NOT NULL REFERENCES public.in_process_artists(address) ON UPDATE CASCADE ON DELETE CASCADE,
  filename text NOT NULL,
  content_type text NOT NULL DEFAULT 'application/octet-stream',
  total_chunks integer NOT NULL CHECK (total_chunks > 0 AND total_chunks <= 139),
  total_size_bytes bigint NULL CHECK (
    total_size_bytes IS NULL
    OR (total_size_bytes > 0 AND total_size_bytes <= 555 * 1024 * 1024)
  ),
  status text NOT NULL DEFAULT 'open' CHECK (
    status IN ('open', 'completing', 'done', 'failed', 'expired')
  ),
  created_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '2 hours')
);

CREATE TABLE in_process_chunk_upload_parts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES in_process_chunk_upload_sessions (id) ON DELETE CASCADE,
  chunk_index integer NOT NULL CHECK (chunk_index >= 0 AND chunk_index < 139),
  byte_length integer NOT NULL CHECK (byte_length > 0 AND byte_length <= 4194304),
  blob_url text NOT NULL,
  UNIQUE (session_id, chunk_index)
);

ALTER TABLE in_process_chunk_upload_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE in_process_chunk_upload_parts ENABLE ROW LEVEL SECURITY;

CREATE INDEX in_process_chunk_upload_sessions_artist_address_idx
  ON in_process_chunk_upload_sessions (artist_address);

CREATE INDEX in_process_chunk_upload_sessions_expires_idx
  ON in_process_chunk_upload_sessions (expires_at)
  WHERE status = 'open';
