-- Enable efficient join from creator address to collections filtered by chain.
-- Required for get_in_process_timeline curated=true join-flip: starts from
-- curated artists → wallets → collections (this index) → moments.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_collections_creator_chain_id ON public.in_process_collections (creator, chain_id);
