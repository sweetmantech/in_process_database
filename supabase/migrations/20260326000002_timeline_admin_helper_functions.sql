-- get_creator_hidden: resolve a token's hidden flag for a given artist from in_process_admins
-- token-specific entry takes priority over collection-level (token_id = 0)
CREATE OR REPLACE FUNCTION public.get_creator_hidden (
  p_collection UUID,
  p_token_id NUMERIC,
  p_artist_address TEXT
) returns BOOLEAN language sql stable AS $$
  SELECT COALESCE(
    (SELECT hidden
     FROM in_process_admins
     WHERE collection = p_collection
       AND (token_id = p_token_id OR token_id = 0)
       AND artist_address = p_artist_address
     ORDER BY CASE WHEN token_id = p_token_id THEN 0 ELSE 1 END
     LIMIT 1),
    false
  )
$$;

-- get_moment_admins_json: return the full admin list for a moment as a JSON array
CREATE OR REPLACE FUNCTION public.get_moment_admins_json (p_collection UUID, p_token_id NUMERIC) returns JSON language sql stable AS $$
  SELECT json_agg(
    json_build_object('address', adm.artist_address, 'hidden', adm.hidden)
    ORDER BY adm.granted_at ASC
  ) FILTER (WHERE adm.artist_address IS NOT NULL)
  FROM (
    SELECT DISTINCT ON (adm.artist_address)
      adm.artist_address,
      adm.hidden,
      adm.granted_at
    FROM in_process_admins adm
    WHERE adm.collection = p_collection
      AND (adm.token_id = p_token_id OR adm.token_id = 0)
    ORDER BY adm.artist_address,
      CASE WHEN adm.token_id = p_token_id THEN 0 ELSE 1 END,
      adm.granted_at ASC
  ) adm
$$;

-- moment_is_visible: true when p_hidden=true (admin override) or no admin has hidden this moment
CREATE OR REPLACE FUNCTION public.moment_is_visible (
  p_collection UUID,
  p_token_id NUMERIC,
  p_hidden BOOLEAN
) returns BOOLEAN language sql stable AS $$
  SELECT
    p_hidden = true
    OR NOT EXISTS (
      SELECT 1 FROM in_process_admins adm_check
      WHERE adm_check.collection = p_collection
        AND (adm_check.token_id = p_token_id OR adm_check.token_id = 0)
        AND adm_check.hidden = true
    )
$$;
