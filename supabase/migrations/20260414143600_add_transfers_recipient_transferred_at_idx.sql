CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_transfers_recipient_transferred_at_desc
  ON public.in_process_transfers USING btree (recipient, transferred_at DESC);
