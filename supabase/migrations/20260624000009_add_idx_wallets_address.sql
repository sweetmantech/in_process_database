-- Index on in_process_wallets(address) to support creator-to-artist joins.
--
-- Every stats RPC resolves collection creators to artist UUIDs via:
--   INNER JOIN in_process_wallets w ON w.address = c.creator
-- and the p_artist address filter via:
--   SELECT w2.artist FROM in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
--
-- Without this index both lookups fall back to a hash join or seq scan.
-- With it the planner can use a nested loop index scan per creator address.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_wallets_address ON public.in_process_wallets (address);
