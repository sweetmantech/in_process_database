-- Platform analytics stats: six KPI counts for a period (and optional artist filter).
-- day/week/month also return previous-period counts for vs-prev delta_pct in the API.
-- all returns current counts only (prev columns are NULL).
CREATE OR REPLACE FUNCTION public.get_analytics_stats (
  p_period TEXT DEFAULT 'week',
  p_artist TEXT DEFAULT NULL
) returns TABLE (
  moments_created BIGINT,
  moments_airdropped BIGINT,
  moments_collected BIGINT,
  active_artists BIGINT,
  collectors BIGINT,
  artists_collectors BIGINT,
  moments_created_prev BIGINT,
  moments_airdropped_prev BIGINT,
  moments_collected_prev BIGINT,
  active_artists_prev BIGINT,
  collectors_prev BIGINT,
  artists_collectors_prev BIGINT
) language plpgsql stable AS $$
DECLARE
  v_interval INTERVAL;
  v_start TIMESTAMPTZ;
  v_prev_start TIMESTAMPTZ;
BEGIN
  IF p_period IS NULL OR p_period = 'all' THEN
    RETURN QUERY
    WITH active_artists AS MATERIALIZED (
      SELECT a.id AS artist_id
      FROM public.in_process_artists a
      WHERE a.username IS NOT NULL
        AND a.username != ''
        AND (
          p_artist IS NULL
          OR a.id IN (
            SELECT w2.artist
            FROM public.in_process_wallets w2
            WHERE w2.address = LOWER(p_artist)
            UNION
            SELECT a2.id
            FROM public.in_process_artists a2
            WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    active_collections AS MATERIALIZED (
      SELECT c.id AS collection_id, aa.artist_id
      FROM active_artists aa
      INNER JOIN public.in_process_wallets w ON w.artist = aa.artist_id
      INNER JOIN public.in_process_collections c ON c.creator = w.address
        AND c.protocol = 'in_process'
        AND c.chain_id = 8453
    ),
    artist_moments AS MATERIALIZED (
      SELECT ac.artist_id, m.id AS moment_id
      FROM active_collections ac
      INNER JOIN public.in_process_moments m ON m.collection = ac.collection_id
    ),
    airdrop_transfers AS (
      SELECT t.id
      FROM public.in_process_transfers t
      INNER JOIN artist_moments am ON am.moment_id = t.moment
      WHERE t.value IS NULL
        AND t.recipient NOT IN (
          SELECT w3.address
          FROM public.in_process_wallets w3
          WHERE w3.artist = am.artist_id
        )
    ),
    paid_transfers AS MATERIALIZED (
      SELECT aa.artist_id
      FROM active_artists aa
      INNER JOIN public.in_process_wallets w ON w.artist = aa.artist_id
      INNER JOIN public.in_process_transfers t ON t.recipient = w.address
        AND t.value IS NOT NULL
      INNER JOIN public.in_process_moments m ON m.id = t.moment
      INNER JOIN public.in_process_collections c ON c.id = m.collection
        AND c.protocol = 'in_process'
        AND c.chain_id = 8453
    ),
    created_artists AS (
      SELECT DISTINCT am.artist_id
      FROM artist_moments am
    ),
    collected_artists AS (
      SELECT DISTINCT pt.artist_id
      FROM paid_transfers pt
    )
    SELECT
      (SELECT COUNT(*)::BIGINT FROM artist_moments),
      (SELECT COUNT(*)::BIGINT FROM airdrop_transfers),
      (SELECT COUNT(*)::BIGINT FROM paid_transfers),
      (SELECT COUNT(*)::BIGINT FROM created_artists),
      (SELECT COUNT(*)::BIGINT FROM collected_artists),
      (
        SELECT COUNT(*)::BIGINT
        FROM created_artists ca
        INNER JOIN collected_artists col ON col.artist_id = ca.artist_id
      ),
      NULL::BIGINT,
      NULL::BIGINT,
      NULL::BIGINT,
      NULL::BIGINT,
      NULL::BIGINT,
      NULL::BIGINT;
    RETURN;
  END IF;

  v_interval := CASE p_period
    WHEN 'day'   THEN INTERVAL '1 day'
    WHEN 'week'  THEN INTERVAL '7 days'
    WHEN 'month' THEN INTERVAL '30 days'
    ELSE               INTERVAL '7 days'
  END;
  v_start := NOW() - v_interval;
  v_prev_start := NOW() - v_interval * 2;

  RETURN QUERY
  WITH artist_moments AS MATERIALIZED (
    SELECT w.artist AS artist_id, m.id AS moment_id, m.created_at
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w ON w.address = c.creator
    INNER JOIN public.in_process_artists a ON a.id = w.artist
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND m.created_at >= v_prev_start
      AND a.username IS NOT NULL
      AND a.username != ''
      AND (
        p_artist IS NULL
        OR w.artist IN (
          SELECT w2.artist
          FROM public.in_process_wallets w2
          WHERE w2.address = LOWER(p_artist)
          UNION
          SELECT a2.id
          FROM public.in_process_artists a2
          WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  current_moment_rows AS (
    SELECT artist_id, moment_id
    FROM artist_moments
    WHERE created_at >= v_start
  ),
  prev_moment_rows AS (
    SELECT artist_id, moment_id
    FROM artist_moments
    WHERE created_at >= v_prev_start
      AND created_at < v_start
  ),
  current_airdrop_transfers AS (
    SELECT t.id
    FROM public.in_process_transfers t
    INNER JOIN current_moment_rows am ON am.moment_id = t.moment
    WHERE t.value IS NULL
      AND t.recipient NOT IN (
        SELECT w3.address
        FROM public.in_process_wallets w3
        WHERE w3.artist = am.artist_id
      )
  ),
  prev_airdrop_transfers AS (
    SELECT t.id
    FROM public.in_process_transfers t
    INNER JOIN prev_moment_rows am ON am.moment_id = t.moment
    WHERE t.value IS NULL
      AND t.recipient NOT IN (
        SELECT w3.address
        FROM public.in_process_wallets w3
        WHERE w3.artist = am.artist_id
      )
  ),
  paid_transfers AS MATERIALIZED (
    SELECT w.artist AS artist_id, t.id AS transfer_id, t.transferred_at
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w ON w.address = t.recipient
    INNER JOIN public.in_process_artists a ON a.id = w.artist
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND t.transferred_at >= v_prev_start
      AND a.username IS NOT NULL
      AND a.username != ''
      AND (
        p_artist IS NULL
        OR w.artist IN (
          SELECT w2.artist
          FROM public.in_process_wallets w2
          WHERE w2.address = LOWER(p_artist)
          UNION
          SELECT a2.id
          FROM public.in_process_artists a2
          WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  current_paid_transfers AS (
    SELECT artist_id, transfer_id
    FROM paid_transfers
    WHERE transferred_at >= v_start
  ),
  prev_paid_transfers AS (
    SELECT artist_id, transfer_id
    FROM paid_transfers
    WHERE transferred_at >= v_prev_start
      AND transferred_at < v_start
  ),
  current_created_artists AS (
    SELECT DISTINCT artist_id FROM current_moment_rows
  ),
  prev_created_artists AS (
    SELECT DISTINCT artist_id FROM prev_moment_rows
  ),
  current_collected_artists AS (
    SELECT DISTINCT artist_id FROM current_paid_transfers
  ),
  prev_collected_artists AS (
    SELECT DISTINCT artist_id FROM prev_paid_transfers
  )
  SELECT
    (SELECT COUNT(*)::BIGINT FROM current_moment_rows),
    (SELECT COUNT(*)::BIGINT FROM current_airdrop_transfers),
    (SELECT COUNT(*)::BIGINT FROM current_paid_transfers),
    (SELECT COUNT(*)::BIGINT FROM current_created_artists),
    (SELECT COUNT(*)::BIGINT FROM current_collected_artists),
    (
      SELECT COUNT(*)::BIGINT
      FROM current_created_artists ca
      INNER JOIN current_collected_artists col ON col.artist_id = ca.artist_id
    ),
    (SELECT COUNT(*)::BIGINT FROM prev_moment_rows),
    (SELECT COUNT(*)::BIGINT FROM prev_airdrop_transfers),
    (SELECT COUNT(*)::BIGINT FROM prev_paid_transfers),
    (SELECT COUNT(*)::BIGINT FROM prev_created_artists),
    (SELECT COUNT(*)::BIGINT FROM prev_collected_artists),
    (
      SELECT COUNT(*)::BIGINT
      FROM prev_created_artists ca
      INNER JOIN prev_collected_artists col ON col.artist_id = ca.artist_id
    );
END;
$$;
