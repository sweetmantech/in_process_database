CREATE INDEX CONCURRENTLY if NOT EXISTS idx_transfers_airdrop_moment_recipient ON public.in_process_transfers (moment) include (recipient)
WHERE
  value IS NULL;
