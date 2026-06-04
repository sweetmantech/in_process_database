-- Replaces the Supabase JS client query in getInProcessMomentsTotalCnt.ts,
-- which broke when in_process_collections.creator was repointed from
-- in_process_artists to in_process_wallets (migration 20260527000017).
-- The direct FK from collections → artists no longer exists, so PostgREST
-- can't resolve the !inner join.  This RPC does the same count in plain SQL.
CREATE OR REPLACE FUNCTION public.get_moments_total_cnt (p_chain_id INT DEFAULT 8453) returns BIGINT language sql stable AS $$
  SELECT COUNT(m.id)::bigint
  FROM public.in_process_moments   m
  INNER JOIN public.in_process_collections c ON c.id          = m.collection
  INNER JOIN public.in_process_wallets     w ON w.address      = c.creator
  INNER JOIN public.in_process_artists     a ON a.id           = w.artist
  WHERE m.uri        != ''
    AND c.chain_id    = p_chain_id
    AND c.protocol    = 'in_process'
    AND a.username   IS NOT NULL
    AND a.username   != '';
$$;
