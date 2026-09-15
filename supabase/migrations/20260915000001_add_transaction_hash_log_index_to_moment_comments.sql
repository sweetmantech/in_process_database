-- Immutable on-chain identifiers for mint-comments (no protocol comment_id to
-- key off of), so the async indexer's write and a future eager API-side
-- write for the same event can dedupe safely on (moment, transaction_hash,
-- log_index) instead of colliding on an approximate timestamp match.
-- No separate chain_id column: moment already ties to a specific
-- collection/chain via in_process_moments, so it disambiguates a
-- transaction_hash collision across chains without denormalizing chain_id
-- onto this table too.
-- Nullable: existing rows and protocol comments (which already dedupe on
-- comment_id) leave these NULL.
ALTER TABLE public.in_process_moment_comments
ADD COLUMN IF NOT EXISTS transaction_hash TEXT,
ADD COLUMN IF NOT EXISTS log_index INTEGER;
