CREATE OR REPLACE FUNCTION public.timeline_filtered_ids (
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE,
  p_protocol TEXT DEFAULT NULL
) returns TABLE (
  moment_id UUID,
  moment_token_id NUMERIC,
  moment_released_at TIMESTAMPTZ
) language plpgsql stable AS $function$
BEGIN
  IF p_curated AND p_mime IS NOT NULL THEN
    RETURN QUERY
    WITH curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    )
    SELECT DISTINCT m.id, m.token_id, m.released_at
    FROM curated_addresses ca
    INNER JOIN in_process_collections c ON c.creator = ca.address
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
    INNER JOIN in_process_moments m ON m.collection = c.id
    INNER JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE meta.content->>'mime' LIKE p_mime
      AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
      AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = ca.artist
      ));

  ELSIF p_curated THEN
    RETURN QUERY
    WITH curated_addresses AS MATERIALIZED (
      SELECT w.address, w.artist
      FROM in_process_artists a
      INNER JOIN in_process_wallets w ON w.artist = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
    )
    SELECT DISTINCT m.id, m.token_id, m.released_at
    FROM curated_addresses ca
    INNER JOIN in_process_collections c ON c.creator = ca.address
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
    INNER JOIN in_process_moments m ON m.collection = c.id
    WHERE
      moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = ca.artist
      ))
      AND NOT EXISTS (
        SELECT 1 FROM in_process_metadata meta2
        WHERE meta2.moment = m.id
          AND meta2.external_url LIKE '%/collect/base:%/%'
      );

  ELSIF p_mime IS NOT NULL THEN
    RETURN QUERY
    SELECT DISTINCT m.id, m.token_id, m.released_at
    FROM in_process_metadata meta
    INNER JOIN in_process_moments m ON m.id = meta.moment
    INNER JOIN in_process_collections c ON m.collection = c.id
    LEFT JOIN in_process_wallets w_creator ON w_creator.address = c.creator
    WHERE meta.content->>'mime' LIKE p_mime
      AND (meta.content->>'uri' IS NOT NULL AND meta.content->>'uri' != '')
      AND (meta.external_url IS NULL OR meta.external_url NOT LIKE '%/collect/base:%/%')
      AND (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden WHERE moment = m.id AND artist = w_creator.artist
      ));

  ELSE
    RETURN QUERY
    SELECT m.id, m.token_id, m.released_at
    FROM in_process_moments m
    INNER JOIN in_process_collections c ON m.collection = c.id
    WHERE
      (p_chainid IS NOT NULL AND c.chain_id = p_chainid OR p_chainid IS NULL AND c.chain_id IN (1, 10, 8453))
      AND (p_protocol IS NULL OR c.protocol::text = p_protocol)
      AND moment_matches_period(m.created_at, p_period)
      AND moment_matches_channel(m.id, p_channel)
      AND (p_hidden = true OR NOT EXISTS (
        SELECT 1 FROM in_process_hidden h
        INNER JOIN in_process_wallets w_creator ON w_creator.artist = h.artist
        WHERE h.moment = m.id AND w_creator.address = c.creator
      ))
      AND NOT EXISTS (
        SELECT 1 FROM in_process_metadata meta2
        WHERE meta2.moment = m.id
          AND meta2.external_url LIKE '%/collect/base:%/%'
      );
  END IF;
END;
$function$;
