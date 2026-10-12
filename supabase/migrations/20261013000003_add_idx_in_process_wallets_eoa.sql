CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_wallets_eoa ON in_process_wallets (eoa)
WHERE
  eoa IS NOT NULL;
