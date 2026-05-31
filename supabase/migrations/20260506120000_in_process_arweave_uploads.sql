CREATE TABLE in_process_arweave_uploads (
  id              uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  arweave_uri     text          NOT NULL,
  winc_cost       text          NOT NULL,
  usdc_cost        numeric(20,8),
  file_size_bytes bigint        NOT NULL,
  content_type    text          NOT NULL,
  artist_address  text          NOT NULL REFERENCES in_process_artists(address),
  created_at      timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX in_process_arweave_uploads_artist_created_idx
  ON in_process_arweave_uploads (artist_address, created_at);
