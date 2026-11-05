ALTER TABLE in_process_artists
ADD COLUMN handle TEXT NULL;

ALTER TABLE in_process_artists
ADD CONSTRAINT in_process_artists_handle_format CHECK (
  handle IS NULL
  OR (
    handle ~ '^[a-z0-9][a-z0-9._-]{1,28}[a-z0-9]$'
    AND handle !~ '^0x'
  )
);

ALTER TABLE in_process_artists
ADD CONSTRAINT in_process_artists_handle_key UNIQUE (handle);
