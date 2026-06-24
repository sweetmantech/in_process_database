-- idx_in_process_collections_chain_id(chain_id)
-- Superseded by idx_collections_chain_id_id(chain_id, id) added in 000004:
-- the composite index covers all chain_id-only predicates as its leading column.
DROP INDEX CONCURRENTLY if EXISTS public.idx_in_process_collections_chain_id;
