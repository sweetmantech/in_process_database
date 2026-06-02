CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transfers_airdrop_moment_recipient
  ON public.in_process_transfers (moment)
  INCLUDE (recipient)
  WHERE value IS NULL;
