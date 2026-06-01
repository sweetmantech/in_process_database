ALTER TABLE in_process_artists_v2
  ADD CONSTRAINT in_process_artists_v2_username_not_empty
  CHECK (username IS NULL OR username != '');
