ALTER TABLE in_process_artists
ADD COLUMN default_collection UUID NULL REFERENCES in_process_collections (id) ON DELETE SET NULL;
