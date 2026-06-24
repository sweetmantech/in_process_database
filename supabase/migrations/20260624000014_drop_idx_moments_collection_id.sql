-- idx_moments_collection_id(collection, id)
-- No query in the codebase sorts or ranges on id within a collection.
-- All timeline ORDER BY clauses use (created_at DESC, token_id DESC), covered by
-- idx_in_process_moments_collection_created_at(collection, created_at).
-- Point lookups on id use the primary key index directly.
DROP INDEX CONCURRENTLY if EXISTS public.idx_moments_collection_id;
