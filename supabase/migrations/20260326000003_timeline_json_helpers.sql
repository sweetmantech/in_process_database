-- build_moment_json: assemble the standard moment JSON object returned by all timeline functions
CREATE OR REPLACE FUNCTION public.build_moment_json (
  p_address TEXT,
  p_token_id NUMERIC,
  p_chain_id NUMERIC,
  p_protocol TEXT,
  p_id UUID,
  p_uri TEXT,
  p_creator TEXT,
  p_creator_username TEXT,
  p_creator_hidden BOOLEAN,
  p_collection UUID,
  p_metadata JSON,
  p_created_at TIMESTAMPTZ
) returns JSON language sql stable AS $$
  SELECT json_build_object(
    'address',    p_address,
    'token_id',   p_token_id::text,
    'chain_id',   p_chain_id,
    'protocol',   p_protocol,
    'id',         p_id,
    'uri',        p_uri,
    'creator',    json_build_object('address', p_creator, 'username', p_creator_username, 'hidden', p_creator_hidden),
    'admins',     COALESCE(get_moment_admins_json(p_collection, p_token_id), '[]'::json),
    'created_at', p_created_at,
    'metadata',   p_metadata
  )
$$;

-- build_timeline_result: assemble the standard paginated timeline response
CREATE OR REPLACE FUNCTION public.build_timeline_result (
  p_moments JSON,
  p_total_count INT,
  p_capped_limit INT,
  p_clamped_page INT
) returns JSON language sql immutable AS $$
  SELECT json_build_object(
    'moments',    COALESCE(p_moments, '[]'::json),
    'pagination', json_build_object(
      'page',        p_clamped_page,
      'limit',       p_capped_limit,
      'total_pages', CASE WHEN p_total_count > 0 THEN CEIL(p_total_count::numeric / p_capped_limit) ELSE 1 END
    )
  )
$$;
