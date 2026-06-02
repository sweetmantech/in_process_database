CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_transfers_airdrop_moment_transferred_at_desc
  ON public.in_process_transfers (moment, transferred_at DESC)
  WHERE value IS NULL;
