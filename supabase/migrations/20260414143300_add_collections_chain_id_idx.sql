CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_collections_chain_id ON public.in_process_collections USING btree (chain_id);
