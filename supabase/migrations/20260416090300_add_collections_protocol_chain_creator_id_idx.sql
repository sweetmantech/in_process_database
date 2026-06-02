CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_collections_protocol_chain_creator_id
  ON public.in_process_collections (protocol, chain_id, creator, id);
