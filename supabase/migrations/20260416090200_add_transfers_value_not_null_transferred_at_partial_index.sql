CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_transfers_non_null_transferred_at_desc ON public.in_process_transfers USING btree (transferred_at DESC)
WHERE
  value IS NOT NULL;
