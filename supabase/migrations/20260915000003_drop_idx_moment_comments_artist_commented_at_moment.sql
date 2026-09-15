-- Superseded by (chain_id, transaction_hash, log_index) — an immutable,
-- collision-safe key for mint-comments, unlike this approximate-timestamp
-- match. comment_id's unique index is kept as-is for now (protocol comments'
-- dedup key + a data-integrity backstop), pending verification after the
-- planned Supabase comments backfill.
-- Separate file: DROP INDEX CONCURRENTLY cannot share a pipeline with CREATE.
DROP INDEX CONCURRENTLY if EXISTS in_process_moment_comments_artist_commented_at_moment_unique_idx;
