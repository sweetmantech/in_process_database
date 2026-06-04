CREATE OR REPLACE FUNCTION public.get_active_artists_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL
) returns TABLE (
  address TEXT,
  username TEXT,
  moments_created BIGINT,
  airdropped BIGINT,
  telegram_count BIGINT,
  web_count BIGINT,
  api_count BIGINT,
  sms_count BIGINT,
  total_count BIGINT
) language sql stable AS $$
  WITH artist_moments AS MATERIALIZED (
    SELECT
      c.creator AS artist_address,
      m.id,
      m.channel
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND moment_matches_period(m.created_at, p_period)
      AND (
        p_artist IS NULL
        OR c.creator = LOWER(p_artist)
        OR c.creator IN (
          SELECT address
          FROM public.in_process_artists
          WHERE username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  airdrop_counts AS (
    SELECT
      am.artist_address,
      COUNT(*) AS airdropped
    FROM public.in_process_transfers t
    INNER JOIN artist_moments am ON am.id = t.moment
    WHERE t.value IS NULL
      AND t.recipient != am.artist_address
    GROUP BY am.artist_address
  ),
  stats AS (
    SELECT
      a.address,
      a.username,
      COUNT(am.id)                                                            AS moments_created,
      COALESCE(ac.airdropped, 0)                                              AS airdropped,
      COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                    AS telegram_count,
      COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)   AS web_count,
      COUNT(am.id) FILTER (WHERE am.channel = 'api')                         AS api_count,
      COUNT(am.id) FILTER (WHERE am.channel = 'sms')                         AS sms_count
    FROM public.in_process_artists a
    INNER JOIN artist_moments am ON am.artist_address = a.address
    LEFT JOIN airdrop_counts ac ON ac.artist_address = a.address
    WHERE a.username IS NOT NULL
      AND a.username != ''
    GROUP BY a.address, a.username, ac.airdropped
  )
  SELECT
    s.address,
    s.username,
    s.moments_created,
    s.airdropped,
    s.telegram_count,
    s.web_count,
    s.api_count,
    s.sms_count,
    COUNT(*) OVER () AS total_count
  FROM stats s
  ORDER BY s.moments_created DESC
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;
