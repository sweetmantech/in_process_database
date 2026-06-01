-- Renames get_artist_collections → get_collections and extends it to support:
--   p_addresses : address-based lookup (single or batch, no moments filter)
-- Also adds creator_username via join with in_process_artists.
DROP FUNCTION IF EXISTS public.get_artist_collections(text, int, int, int);
CREATE OR REPLACE FUNCTION public.get_collections(
  p_artist    text    DEFAULT NULL,
  p_chainid   int     DEFAULT NULL,
  p_addresses text[]  DEFAULT NULL,
  p_limit     int     DEFAULT 20,
  p_page      int     DEFAULT 1
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit    int     := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page    int     := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val      int     := (clamped_page - 1) * capped_limit;
  -- address-based lookups skip the moments filter and pagination
  v_addr_mode     boolean := (p_addresses IS NOT NULL);
  v_collections   json;
  v_total_count   int;
BEGIN
  WITH filtered AS MATERIALIZED (
    SELECT
      c.id, c.address, c.name, c.chain_id, c.created_at,
      c.uri, c.protocol, c.creator,
      art.username AS creator_username
    FROM in_process_collections c
    LEFT JOIN in_process_artists art ON art.address = c.creator
    WHERE
      -- addresses filter
      (p_addresses IS NULL OR c.address = ANY(p_addresses))
      -- list-mode filters
      AND (p_artist  IS NULL OR c.creator  = LOWER(p_artist))
      AND (p_chainid IS NULL OR c.chain_id = p_chainid)
      -- moments filter only applies in list mode
      AND (v_addr_mode OR EXISTS (
        SELECT 1
        FROM in_process_moments m
        INNER JOIN in_process_metadata meta ON meta.moment = m.id
        WHERE m.collection = c.id
          AND meta.content->>'uri' IS NOT NULL
          AND meta.content->>'uri' != ''
      ))
    ORDER BY c.created_at DESC
  ),
  total AS (SELECT COUNT(*)::int AS cnt FROM filtered),
  paged AS (
    SELECT * FROM filtered
    ORDER BY created_at DESC
    LIMIT  CASE WHEN v_addr_mode THEN NULL ELSE capped_limit END
    OFFSET CASE WHEN v_addr_mode THEN 0    ELSE offset_val   END
  )
  SELECT
    (SELECT cnt FROM total),
    json_agg(
      json_build_object(
        'id',              p.id,
        'address',         p.address,
        'name',            p.name,
        'chain_id',        p.chain_id,
        'created_at',      p.created_at,
        'uri',             p.uri,
        'protocol',        p.protocol,
        'creator',         p.creator,
        'creator_username', p.creator_username,
        'admins', (
          SELECT COALESCE(
            json_agg(json_build_object(
              'artist_address', adm.artist_address,
              'token_id',       adm.token_id
            )),
            '[]'::json
          )
          FROM in_process_admins adm
          WHERE adm.collection = p.id
        )
      )
      ORDER BY p.created_at DESC
    )
  INTO v_total_count, v_collections
  FROM paged p;

  RETURN json_build_object(
    'collections', COALESCE(v_collections, '[]'::json),
    'total_count',  COALESCE(v_total_count, 0)
  );
END;
$function$;
