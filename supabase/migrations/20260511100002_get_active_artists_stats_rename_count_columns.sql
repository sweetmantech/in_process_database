-- Rebuilds get_active_artists_stats with sortable params and renamed counts:
--   moments_created -> created_count, airdropped -> airdropped_count
-- Postgres requires DROP first because RETURNS TABLE column names cannot be
-- changed via CREATE OR REPLACE. We drop both possible prior signatures so this
-- migration is safe regardless of which version is currently installed.
DROP FUNCTION if EXISTS public.get_active_artists_stats (TEXT, INT, INT, TEXT);

DROP FUNCTION if EXISTS public.get_active_artists_stats (TEXT, INT, INT, TEXT, TEXT, TEXT);

CREATE FUNCTION public.get_active_artists_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'created_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  address TEXT,
  username TEXT,
  created_count BIGINT,
  airdropped_count BIGINT,
  telegram_count BIGINT,
  web_count BIGINT,
  api_count BIGINT,
  sms_count BIGINT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT := LOWER(COALESCE(p_sort_by, 'created_count'));
  v_sort_order TEXT := LOWER(COALESCE(p_sort_order, 'desc'));
BEGIN
  IF v_sort_by NOT IN (
    'created_count', 'airdropped_count',
    'telegram_count', 'web_count', 'api_count', 'sms_count'
  ) THEN
    v_sort_by := 'created_count';
  END IF;

  IF v_sort_order NOT IN ('asc', 'desc') THEN
    v_sort_order := 'desc';
  END IF;

  IF v_sort_by = 'airdropped_count' THEN
    -- Sorting by airdropped_count requires global airdrop aggregation
    -- across every matching artist before paginating.
    RETURN QUERY
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
            SELECT a2.address
            FROM public.in_process_artists a2
            WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    airdrop_counts AS (
      SELECT
        am.artist_address,
        SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
      FROM artist_moments am
      CROSS JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM public.in_process_transfers t
        WHERE t.moment = am.id
          AND t.value IS NULL
          AND t.recipient != am.artist_address
      ) airdrop_count
      GROUP BY am.artist_address
    ),
    stats AS (
      SELECT
        a.address,
        a.username,
        COUNT(am.id)                                                          AS created_count,
        COALESCE(ac.airdropped_count, 0)                                      AS airdropped_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                   AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)  AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                        AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                        AS sms_count
      FROM public.in_process_artists a
      INNER JOIN artist_moments am ON am.artist_address = a.address
      LEFT JOIN airdrop_counts ac ON ac.artist_address = a.address
      WHERE a.username IS NOT NULL
        AND a.username != ''
      GROUP BY a.address, a.username, ac.airdropped_count
    )
    SELECT
      s.address,
      s.username,
      s.created_count,
      s.airdropped_count,
      s.telegram_count,
      s.web_count,
      s.api_count,
      s.sms_count,
      COUNT(*) OVER () AS total_count
    FROM stats s
    ORDER BY
      CASE WHEN v_sort_order = 'asc'  THEN s.airdropped_count END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN s.airdropped_count END DESC NULLS LAST
    LIMIT p_limit OFFSET (p_page - 1) * p_limit;

  ELSE
    -- Fast path: paginate stats first, then aggregate airdrops only for the
    -- paged set of artists (matches the v007 optimization).
    RETURN QUERY
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
            SELECT a2.address
            FROM public.in_process_artists a2
            WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    stats_base AS (
      SELECT
        a.address,
        a.username,
        COUNT(am.id)                                                          AS created_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                   AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)  AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                        AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                        AS sms_count
      FROM public.in_process_artists a
      INNER JOIN artist_moments am ON am.artist_address = a.address
      WHERE a.username IS NOT NULL
        AND a.username != ''
      GROUP BY a.address, a.username
    ),
    paged AS (
      SELECT
        sb.address,
        sb.username,
        sb.created_count,
        sb.telegram_count,
        sb.web_count,
        sb.api_count,
        sb.sms_count,
        COUNT(*) OVER () AS total_count
      FROM stats_base sb
      ORDER BY
        CASE WHEN v_sort_order = 'asc' THEN
          CASE v_sort_by
            WHEN 'created_count'   THEN sb.created_count
            WHEN 'telegram_count'  THEN sb.telegram_count
            WHEN 'web_count'       THEN sb.web_count
            WHEN 'api_count'       THEN sb.api_count
            WHEN 'sms_count'       THEN sb.sms_count
          END
        END ASC,
        CASE WHEN v_sort_order = 'desc' THEN
          CASE v_sort_by
            WHEN 'created_count'   THEN sb.created_count
            WHEN 'telegram_count'  THEN sb.telegram_count
            WHEN 'web_count'       THEN sb.web_count
            WHEN 'api_count'       THEN sb.api_count
            WHEN 'sms_count'       THEN sb.sms_count
          END
        END DESC
      LIMIT p_limit OFFSET (p_page - 1) * p_limit
    ),
    airdrop_counts AS (
      SELECT
        am.artist_address,
        SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
      FROM artist_moments am
      INNER JOIN paged p ON p.address = am.artist_address
      CROSS JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM public.in_process_transfers t
        WHERE t.moment = am.id
          AND t.value IS NULL
          AND t.recipient != am.artist_address
      ) airdrop_count
      GROUP BY am.artist_address
    )
    SELECT
      p.address,
      p.username,
      p.created_count,
      COALESCE(ac.airdropped_count, 0) AS airdropped_count,
      p.telegram_count,
      p.web_count,
      p.api_count,
      p.sms_count,
      p.total_count
    FROM paged p
    LEFT JOIN airdrop_counts ac ON ac.artist_address = p.address
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN
        CASE v_sort_by
          WHEN 'created_count'   THEN p.created_count
          WHEN 'telegram_count'  THEN p.telegram_count
          WHEN 'web_count'       THEN p.web_count
          WHEN 'api_count'       THEN p.api_count
          WHEN 'sms_count'       THEN p.sms_count
        END
      END ASC,
      CASE WHEN v_sort_order = 'desc' THEN
        CASE v_sort_by
          WHEN 'created_count'   THEN p.created_count
          WHEN 'telegram_count'  THEN p.telegram_count
          WHEN 'web_count'       THEN p.web_count
          WHEN 'api_count'       THEN p.api_count
          WHEN 'sms_count'       THEN p.sms_count
        END
      END DESC;
  END IF;
END;
$$;
