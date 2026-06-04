-- Refactor get_collection_timeline v2: use build_moment_json + build_timeline_result helpers
DROP FUNCTION if EXISTS public.get_collection_timeline (TEXT, INTEGER, INTEGER, NUMERIC, BOOLEAN, TEXT);

CREATE OR REPLACE FUNCTION public.get_collection_timeline (
  p_collection TEXT,
  p_limit INTEGER DEFAULT 100,
  p_page INTEGER DEFAULT 1,
  p_chainid NUMERIC DEFAULT 8453,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_artist TEXT DEFAULT NULL
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit  int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 100), 1000));
  clamped_page  int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int := (clamped_page - 1) * capped_limit;
  v_moments     json;
  v_total_count int;
BEGIN
  WITH
  -- Step 1: apply all filters once, get distinct matching IDs
  filtered_ids AS (
    SELECT DISTINCT m.id, m.token_id, m.created_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      c.address = LOWER(p_collection)
      AND (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_artist IS NULL OR da.username ILIKE p_artist OR da.address = LOWER(p_artist))
      AND moment_is_visible(m.collection, m.token_id, p_hidden)
  ),
  -- Step 2: total count for pagination
  total AS (SELECT COUNT(*) AS cnt FROM filtered_ids),
  -- Step 3: paginate by ID
  paged_ids AS (
    SELECT id FROM filtered_ids
    ORDER BY created_at DESC, token_id DESC
    LIMIT capped_limit OFFSET offset_val
  ),
  -- Step 4: fetch full row data only for the current page
  moment_data AS (
    SELECT
      m.id,
      m.collection,
      m.token_id,
      m.uri,
      m.created_at,
      c.address,
      c.chain_id,
      c.protocol,
      c.creator,
      da.username                                                   AS creator_username,
      get_creator_hidden(m.collection, m.token_id, c.creator)      AS creator_hidden,
      meta.content                                                  AS metadata
    FROM paged_ids pi
    INNER JOIN in_process_moments m ON m.id = pi.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists da ON c.creator = da.address
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
  )
  SELECT
    (SELECT cnt FROM total),
    json_agg(
      build_moment_json(
        md.address, md.token_id, md.chain_id, md.protocol, md.id, md.uri,
        md.creator, md.creator_username, md.creator_hidden,
        md.collection, md.metadata, md.created_at
      )
      ORDER BY md.created_at DESC, md.token_id DESC
    )
  INTO v_total_count, v_moments
  FROM moment_data md;

  RETURN build_timeline_result(v_moments, v_total_count, capped_limit, clamped_page);
END;
$function$;
