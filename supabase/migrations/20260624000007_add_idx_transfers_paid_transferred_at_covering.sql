-- Covering index on in_process_transfers(transferred_at DESC, moment, recipient)
-- WHERE value IS NOT NULL, upgrading the existing single-column partial index:
--   idx_in_process_transfers_non_null_transferred_at_desc (transferred_at DESC) WHERE value IS NOT NULL
--
-- The existing index supports period range scans (transferred_at >= NOW() - interval)
-- but requires a heap fetch for every row to read moment and recipient.
-- Adding moment and recipient as index columns eliminates heap fetches, so
-- period-filtered queries in get_collectors_stats can resolve the full join:
--
--   transfers[transferred_at >= period_start, value IS NOT NULL]
--     → moment: join to in_process_moments → in_process_collections (protocol+chain_id)
--     → recipient: join to in_process_wallets → in_process_artists (username filter)
--
-- all without touching the heap for those two columns.
--
-- The old single-column index is kept: the planner may still prefer it for
-- queries that only need transferred_at (e.g. ORDER BY / cursor pagination).
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_transfers_paid_transferred_at_covering ON public.in_process_transfers (transferred_at DESC, moment, recipient)
WHERE
  value IS NOT NULL;
