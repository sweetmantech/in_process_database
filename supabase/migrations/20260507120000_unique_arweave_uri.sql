ALTER TABLE in_process_arweave_uploads
  ADD CONSTRAINT in_process_arweave_uploads_arweave_uri_unique UNIQUE (arweave_uri);
