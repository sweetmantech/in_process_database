-- idx_in_process_transfers_non_null_transferred_at_desc(transferred_at DESC) WHERE value IS NOT NULL
-- Superseded by idx_transfers_paid_transferred_at_covering(transferred_at DESC, moment, recipient)
-- WHERE value IS NOT NULL added in 000008: the covering index serves every query
-- the single-column version did, with moment and recipient available index-only.
DROP INDEX CONCURRENTLY if EXISTS public.idx_in_process_transfers_non_null_transferred_at_desc;
