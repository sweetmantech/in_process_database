DROP INDEX if EXISTS idx_in_process_artists_username_lower;

CREATE INDEX idx_in_process_artists_username_lower ON in_process_artists (LOWER(username));

DROP INDEX if EXISTS idx_in_process_artists_qualified;

CREATE INDEX idx_in_process_artists_qualified ON in_process_artists (address)
WHERE
  username IS NOT NULL
  AND username <> ''
  AND telegram IS NOT NULL
  AND telegram <> '';

DROP INDEX if EXISTS idx_in_process_artists_username_trgm;

CREATE INDEX if NOT EXISTS idx_in_process_wallets_artist ON in_process_wallets (artist);
