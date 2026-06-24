-- idx_in_process_transfers_airdrop_transferred_at_desc(transferred_at DESC) WHERE value IS NULL
-- No query filters airdrop transfers starting from transferred_at.
-- Every airdrop aggregation (get_active_artists_stats, mv_active_artists_stats)
-- starts from a known moment id and uses
-- idx_transfers_airdrop_moment_recipient(moment) WHERE value IS NULL instead.
DROP INDEX CONCURRENTLY if EXISTS public.idx_in_process_transfers_airdrop_transferred_at_desc;
