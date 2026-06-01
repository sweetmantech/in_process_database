-- Add p_mime filter to get_artist_timeline RPC via in_process_metadata join
CREATE OR REPLACE FUNCTION public.get_artist_timeline(
  p_artist text,
  p_type text DEFAULT NULL,
  p_limit integer DEFAULT 100,
  p_page integer DEFAULT 1,
  p_chainid numeric DEFAULT 8453,
  p_hidden boolean DEFAULT false,
  p_mime text DEFAULT NULL
)
 RETURNS json
 LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val int := (clamped_page - 1) * capped_limit;
  v_moments json;
  v_total_count int;
  v_total_pages int;
BEGIN
  -- Get filtered count (for pagination calculation)
  WITH filtered_moments AS (
    SELECT DISTINCT
      m.id
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' = p_mime)
      AND (
        -- When p_hidden = true, return all moments regardless of hidden status
        -- Default case: artist is the creator
        (
          (p_type IS NULL OR p_type = 'default')
          AND c.creator = LOWER(p_artist)
          AND (
            p_hidden = true OR
            COALESCE(
              (SELECT hidden FROM in_process_admins
               WHERE collection = m.collection
                 AND (token_id = m.token_id OR token_id = 0)
                 AND artist_address = c.creator
               ORDER BY CASE WHEN token_id = m.token_id THEN 0 ELSE 1 END
               LIMIT 1),
              false
            ) = false
          )
        )
        OR
        -- Mutual case: artist is NOT the creator but IS in the admins list
        (
          (p_type IS NULL OR p_type = 'mutual')
          AND c.creator != LOWER(p_artist)
          AND EXISTS (
            SELECT 1 FROM in_process_admins adm_check
            WHERE adm_check.collection = m.collection
            AND (adm_check.token_id = m.token_id OR adm_check.token_id = 0)
            AND adm_check.artist_address = LOWER(p_artist)
          )
          AND (
            p_hidden = true OR
            COALESCE(
              (SELECT hidden FROM in_process_admins
               WHERE collection = m.collection
                 AND (token_id = m.token_id OR token_id = 0)
                 AND artist_address = LOWER(p_artist)
               ORDER BY CASE WHEN token_id = m.token_id THEN 0 ELSE 1 END
               LIMIT 1),
              false
            ) = false
          )
        )
      )
  )
  SELECT COUNT(*) INTO v_total_count FROM filtered_moments;

  -- Get moments array with admins
  WITH moment_data AS (
    SELECT DISTINCT
      m.id,
      m.collection,
      m.token_id,
      m.uri,
      m.created_at,
      c.address,
      c.chain_id,
      c.protocol,
      c.creator,
      -- Get creator info
      da.username AS creator_username,
      -- Get creator hidden status from admins table
      -- Priority: exact token_id match, if not found default to false
      COALESCE(
        (SELECT hidden FROM in_process_admins
         WHERE collection = m.collection
           AND (token_id = m.token_id OR token_id = 0)
           AND artist_address = c.creator
         ORDER BY CASE WHEN token_id = m.token_id THEN 0 ELSE 1 END
         LIMIT 1),
        false
      ) AS creator_hidden
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' = p_mime)
      AND (
        -- When p_hidden = true, return all moments regardless of hidden status
        -- Default case: artist is the creator
        (
          (p_type IS NULL OR p_type = 'default')
          AND c.creator = LOWER(p_artist)
          AND (
            p_hidden = true OR
            COALESCE(
              (SELECT hidden FROM in_process_admins
               WHERE collection = m.collection
                 AND (token_id = m.token_id OR token_id = 0)
                 AND artist_address = c.creator
               ORDER BY CASE WHEN token_id = m.token_id THEN 0 ELSE 1 END
               LIMIT 1),
              false
            ) = false
          )
        )
        OR
        -- Mutual case: artist is NOT the creator but IS in the admins list
        (
          (p_type IS NULL OR p_type = 'mutual')
          AND c.creator != LOWER(p_artist)
          AND EXISTS (
            SELECT 1 FROM in_process_admins adm_check
            WHERE adm_check.collection = m.collection
            AND (adm_check.token_id = m.token_id OR adm_check.token_id = 0)
            AND adm_check.artist_address = LOWER(p_artist)
          )
          AND (
            p_hidden = true OR
            COALESCE(
              (SELECT hidden FROM in_process_admins
               WHERE collection = m.collection
                 AND (token_id = m.token_id OR token_id = 0)
                 AND artist_address = LOWER(p_artist)
               ORDER BY CASE WHEN token_id = m.token_id THEN 0 ELSE 1 END
               LIMIT 1),
              false
            ) = false
          )
        )
      )
  ),
  admin_data AS (
    SELECT
      md.id AS moment_id,
      json_agg(
        json_build_object(
          'address', adm.artist_address,
          'hidden', adm.hidden
        )
        ORDER BY adm.granted_at ASC
      ) FILTER (WHERE adm.artist_address IS NOT NULL) AS admins_array
    FROM moment_data md
    LEFT JOIN LATERAL (
      SELECT DISTINCT ON (adm.artist_address)
        adm.artist_address,
        adm.hidden,
        adm.granted_at
      FROM in_process_admins adm
      WHERE adm.collection = md.collection
        AND (adm.token_id = md.token_id OR adm.token_id = 0)
      ORDER BY adm.artist_address,
        CASE WHEN adm.token_id = md.token_id THEN 0 ELSE 1 END,
        adm.granted_at ASC
    ) adm ON true
    GROUP BY md.id
  )
  SELECT json_agg(
    json_build_object(
      'address', moment_result.address,
      'token_id', moment_result.token_id,
      'chain_id', moment_result.chain_id,
      'protocol', moment_result.protocol,
      'id', moment_result.id,
      'uri', moment_result.uri,
      'creator', moment_result.creator,
      'admins', moment_result.admins,
      'created_at', moment_result.created_at
    )
  ) INTO v_moments
  FROM (
    SELECT
      md.address,
      md.token_id::text AS token_id,
      md.chain_id,
      md.protocol,
      md.id,
      md.uri,
      json_build_object(
        'address', md.creator,
        'username', md.creator_username,
        'hidden', md.creator_hidden
      ) AS creator,
      COALESCE(ad.admins_array, '[]'::json) AS admins,
      md.created_at
    FROM moment_data md
    LEFT JOIN admin_data ad ON md.id = ad.moment_id
    ORDER BY md.created_at DESC
    LIMIT capped_limit OFFSET offset_val
  ) moment_result;

  -- Calculate total pages
  v_total_pages := CASE WHEN v_total_count > 0 THEN CEIL(v_total_count::numeric / capped_limit) ELSE 1 END;

  -- Return JSON response matching API format
  RETURN json_build_object(
    'moments', COALESCE(v_moments, '[]'::json),
    'pagination', json_build_object(
      'page', clamped_page,
      'limit', capped_limit,
      'total_pages', v_total_pages
    )
  );
END;
$function$
;
