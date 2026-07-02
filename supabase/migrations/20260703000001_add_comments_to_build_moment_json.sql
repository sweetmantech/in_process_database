-- Add comments count to build_moment_json (used by all 3 timeline RPCs).
-- Returns integer count only, e.g. "comments": 7 — not the full comment list.
-- Depends on: 20260630000001 (build_moment_json with sale param).
-- ── build_moment_json ─────────────────────────────────────────────────────────
-- Use CREATE OR REPLACE only — timeline RPCs depend on this function;
-- dropping the current overload would fail without CASCADE.
CREATE OR REPLACE FUNCTION public.build_moment_json (
  p_address TEXT,
  p_token_id NUMERIC,
  p_chain_id NUMERIC,
  p_protocol TEXT,
  p_id UUID,
  p_uri TEXT,
  p_creator TEXT,
  p_creator_username TEXT,
  p_collection UUID,
  p_metadata JSON,
  p_created_at TIMESTAMPTZ,
  p_sale JSON DEFAULT NULL
) returns JSON language sql stable AS $$
  SELECT json_build_object(
    'address',        p_address,
    'token_id',       p_token_id::text,
    'chain_id',       p_chain_id,
    'protocol',       p_protocol,
    'id',             p_id,
    'uri',            p_uri,
    'creator',        json_build_object('address', p_creator, 'username', p_creator_username),
    'admins',         COALESCE(get_moment_admins_json(p_collection, p_token_id), '[]'::json),
    'hidden',         COALESCE(
                        (SELECT json_agg(h.artist::text ORDER BY h.artist::text)
                         FROM in_process_hidden h WHERE h.moment = p_id),
                        '[]'::json
                      ),
    'created_at',     p_created_at,
    'metadata',       p_metadata,
    'sale',           p_sale,
    'comments',       (SELECT COUNT(*) FROM in_process_moment_comments c WHERE c.moment = p_id)
  )
$$;
