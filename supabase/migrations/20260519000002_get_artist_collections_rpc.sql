-- Returns collections by artist that have at least one moment with a non-empty
-- content.uri (same filter applied to timeline RPCs in 20260519000001).
CREATE OR REPLACE FUNCTION public.get_artist_collections(
  p_artist  text    DEFAULT NULL,
  p_chainid int     DEFAULT NULL,
  p_limit   int     DEFAULT 20,
  p_page    int     DEFAULT 1
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val   int := (clamped_page - 1) * capped_limit;
  v_collections json;
  v_total_count int;
BEGIN
  WITH filtered AS MATERIALIZED (
    SELECT c.id, c.address, c.name, c.chain_id, c.created_at, c.uri, c.protocol, c.creator
    FROM in_process_collections c
    WHERE (p_artist  IS NULL OR c.creator   = LOWER(p_artist))
      AND (p_chainid IS NULL OR c.chain_id  = p_chainid)
      AND EXISTS (
        SELECT 1 FROM in_process_moments m
        INNER JOIN in_process_metadata meta ON meta.moment = m.id
        WHERE m.collection = c.id
          AND meta.content->>'uri' IS NOT NULL
          AND meta.content->>'uri' != ''
      )
    ORDER BY c.created_at DESC
  ),
  total AS (SELECT COUNT(*)::int AS cnt FROM filtered),
  paged AS (
    SELECT * FROM filtered
    ORDER BY created_at DESC
    LIMIT capped_limit OFFSET offset_val
  )
  SELECT
    (SELECT cnt FROM total),
    json_agg(
      json_build_object(
        'id',         p.id,
        'address',    p.address,
        'name',       p.name,
        'chain_id',   p.chain_id,
        'created_at', p.created_at,
        'uri',        p.uri,
        'protocol',   p.protocol,
        'creator',    p.creator,
        'admins',     (
          SELECT COALESCE(
            json_agg(json_build_object(
              'artist_address', a.artist_address,
              'token_id',       a.token_id
            )),
            '[]'::json
          )
          FROM in_process_admins a
          WHERE a.collection = p.id
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
