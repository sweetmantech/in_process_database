-- Enforce one external wallet per artist
CREATE UNIQUE INDEX if NOT EXISTS idx_in_process_wallets_artist_external_unique ON in_process_wallets (artist)
WHERE
  type = 'external';
