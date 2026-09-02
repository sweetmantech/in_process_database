-- =============================================================================
-- EXPLAIN get_analytics_stats (pre-migration spike)
-- =============================================================================
--
-- Where to run:
--   - Supabase Dashboard → SQL Editor (staging recommended)
--   - psql "$DATABASE_URL" -f scripts/explain_get_analytics_stats.sql
--
-- What it does:
--   1. BEGIN … ROLLBACK so the function is NOT left deployed if you rollback
--   2. CREATE OR REPLACE get_analytics_stats (same as migration)
--   3. EXPLAIN (ANALYZE, BUFFERS) for day / week / month / all
--   4. Optional artist-filter example
--   5. Sanity SELECT (actual row) for week
--
-- WARNING: EXPLAIN ANALYZE executes the query for real. Avoid peak traffic on prod.
-- Look for:
--   - "Execution Time: … ms" (keep well under statement timeout, often ~8s)
--   - Seq Scan on in_process_transfers / in_process_moments
--   - "canceling statement due to statement timeout"
--
-- To keep the function after testing, change final ROLLBACK to COMMIT.
-- =============================================================================

BEGIN;

-- ── migration body (20260903000001_get_analytics_stats_rpc.sql) ─────────────

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

-- ── EXPLAIN: platform-wide (no artist filter) ───────────────────────────────

DO $$ BEGIN RAISE NOTICE '========== EXPLAIN day (platform) =========='; END $$;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)
SELECT *
FROM public.get_analytics_stats('day', NULL);

DO $$ BEGIN RAISE NOTICE '========== EXPLAIN week (platform) =========='; END $$;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)
SELECT *
FROM public.get_analytics_stats('week', NULL);

DO $$ BEGIN RAISE NOTICE '========== EXPLAIN month (platform) =========='; END $$;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)
SELECT *
FROM public.get_analytics_stats('month', NULL);

DO $$ BEGIN RAISE NOTICE '========== EXPLAIN all (platform) =========='; END $$;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)
SELECT *
FROM public.get_analytics_stats('all', NULL);

-- ── EXPLAIN: single-artist filter (edit artist as needed) ─────────────────────

DO $$ BEGIN RAISE NOTICE '========== EXPLAIN week (artist=sweetman) =========='; END $$;
EXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, WAL)
SELECT *
FROM public.get_analytics_stats('week', 'sweetman');

-- ── Sanity: actual numbers for week (compare with existing table RPCs later) ─

DO $$ BEGIN RAISE NOTICE '========== SELECT week (platform) =========='; END $$;
SELECT *
FROM public.get_analytics_stats('week', NULL);

-- ── Optional cross-check vs existing RPC total_count (week) ─────────────────
-- Uncomment after verifying function names exist on your DB.

-- \echo '========== cross-check active_artists total_count =========='
-- SELECT total_count
-- FROM public.get_active_artists_stats('week', 1, 1, NULL, 'created_count', 'desc')
-- LIMIT 1;
--
-- \echo '========== cross-check collectors total_count =========='
-- SELECT total_count
-- FROM public.get_collectors_stats('week', 1, 1, NULL, 'collected_count', 'desc')
-- LIMIT 1;
--
-- \echo '========== cross-check artists_collectors total_count =========='
-- SELECT total_count
-- FROM public.get_artists_collectors_stats('week', 1, 1, NULL, 'total_created_count', 'desc')
-- LIMIT 1;

-- Keep function: COMMIT;
-- Discard function: ROLLBACK;
ROLLBACK;
