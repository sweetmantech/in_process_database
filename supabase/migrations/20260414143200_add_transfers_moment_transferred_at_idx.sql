CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_transfers_moment_transferred_at_desc
  ON public.in_process_transfers USING btree (moment, transferred_at DESC);
