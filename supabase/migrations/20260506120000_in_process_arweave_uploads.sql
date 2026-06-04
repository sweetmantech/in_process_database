CREATE TABLE in_process_arweave_uploads (
  id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
  arweave_uri TEXT NOT NULL,
  winc_cost TEXT NOT NULL,
  usdc_cost NUMERIC(20, 8),
  file_size_bytes BIGINT NOT NULL,
  content_type TEXT NOT NULL,
  artist_address TEXT NOT NULL REFERENCES in_process_artists (address),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX in_process_arweave_uploads_artist_created_idx ON in_process_arweave_uploads (artist_address, created_at);
