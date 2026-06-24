-- Index on in_process_moments(created_at DESC, token_id DESC) to support
-- the ORDER BY used in every get_in_process_timeline branch:
--
--   ORDER BY created_at DESC, token_id DESC
--
-- The existing idx_in_process_moments_collection_created_at is (collection, created_at) ASC,
-- which serves per-collection ordered access but not the global sort across
-- all moments after chain_id filtering. Without this index the planner must
-- sort the entire filtered_ids result set in memory before applying LIMIT/OFFSET.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moments_created_at_desc_token_id_desc ON public.in_process_moments (created_at DESC, token_id DESC);
