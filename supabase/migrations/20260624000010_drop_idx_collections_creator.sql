-- idx_collections_creator(creator)
-- Superseded by idx_collections_creator_chain_id(creator, chain_id):
-- PostgreSQL uses a composite index for leading-column-only predicates,
-- so (creator, chain_id) already covers every query that filtered on creator alone.
DROP INDEX CONCURRENTLY if EXISTS public.idx_collections_creator;
