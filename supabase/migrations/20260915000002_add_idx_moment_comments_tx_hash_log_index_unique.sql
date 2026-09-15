-- Full unique on (moment, transaction_hash, log_index) so PostgREST upsert
-- ON CONFLICT (moment, transaction_hash, log_index) works for mint-comments.
-- moment disambiguates a transaction_hash collision across the different
-- chains this table stores comments from, without a separate chain_id
-- column. Postgres UNIQUE still allows multiple NULL triples (protocol
-- comments, pre-migration rows).
CREATE UNIQUE INDEX CONCURRENTLY if NOT EXISTS in_process_moment_comments_moment_tx_hash_log_index_unique_idx ON public.in_process_moment_comments (moment, transaction_hash, log_index);
