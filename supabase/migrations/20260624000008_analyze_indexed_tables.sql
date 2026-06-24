-- Refresh planner statistics for all tables that received new indexes in
-- migrations 000003–000010. Without ANALYZE the query planner may not choose
-- the new indexes until autovacuum runs on its own schedule.
--
-- Tables and their new indexes:
--   in_process_metadata    ← idx_metadata_collect_url_moment            (000003)
--   in_process_collections ← idx_collections_chain_id_id               (000004)
--   in_process_moments     ← idx_moments_created_at_desc_token_id_desc (000005)
--                          ← idx_moments_created_at_collection          (000006)
--   in_process_transfers   ← idx_transfers_paid_moment_recipient        (000007)
--                          ← idx_transfers_paid_transferred_at_covering (000008)
--   in_process_wallets     ← idx_in_process_wallets_address             (000010)
ANALYZE public.in_process_metadata;

ANALYZE public.in_process_collections;

ANALYZE public.in_process_moments;

ANALYZE public.in_process_transfers;

ANALYZE public.in_process_wallets;
