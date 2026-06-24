-- Optimize period='all' for all 3 stats RPCs by starting from the small side.
--
-- Root cause: period='all' branches started from the large side:
--   get_active_artists_stats    → in_process_moments (262k rows seq scan)
--   get_artists_collectors_stats → in_process_moments (262k) + in_process_transfers (full paid scan)
--   get_collectors_stats        → in_process_transfers (full paid scan, 29,697ms)
--
-- Fix: start every 'all' branch from active_artists (3,328 rows with username).
-- With only 2,488 active moments across those artists, the joins become tiny.
--
-- New execution order for 'all':
--   in_process_artists  (3,328 with username)      ← start here
--   → in_process_wallets (idx_in_process_wallets_artist)
--   → in_process_collections (idx_collections_protocol_chain_creator_id)
--   → in_process_moments (idx_in_process_moments_collection_created_at)
--   → in_process_transfers (PK lookup per moment / per recipient wallet)
--
-- period=day/week/month branches are unchanged — the date filter already
-- limits the result set to a small number of rows in those branches.
--
-- No new indexes required. Existing indexes are sufficient.
-- ── 1. get_active_artists_stats ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_active_artists_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'created_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  artist_id TEXT,
  username TEXT,
  wallets JSONB,
  created_count BIGINT,
  airdropped_count BIGINT,
  telegram_count BIGINT,
  web_count BIGINT,
  api_count BIGINT,
  sms_count BIGINT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT     := LOWER(COALESCE(p_sort_by,    'created_count'));
  v_sort_order TEXT     := LOWER(COALESCE(p_sort_order, 'desc'));
  v_interval   INTERVAL;
BEGIN
  IF v_sort_by NOT IN ('created_count','airdropped_count','telegram_count','web_count','api_count','sms_count') THEN
    v_sort_by := 'created_count';
  END IF;
  IF v_sort_order NOT IN ('asc','desc') THEN
    v_sort_order := 'desc';
  END IF;

  -- ── period='all': start from active_artists (3,328) → collections → moments ─
  IF p_period IS NULL OR p_period = 'all' THEN

    IF v_sort_by = 'airdropped_count' THEN
      RETURN QUERY
      WITH active_artists AS MATERIALIZED (
        SELECT a.id AS artist_id, a.username
        FROM public.in_process_artists a
        WHERE a.username IS NOT NULL AND a.username != ''
          AND (
            p_artist IS NULL
            OR a.id IN (
              SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
              UNION
              SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
            )
          )
      ),
      active_collections AS MATERIALIZED (
        SELECT c.id AS collection_id, aa.artist_id
        FROM active_artists aa
        INNER JOIN public.in_process_wallets w  ON w.artist = aa.artist_id
        INNER JOIN public.in_process_collections c ON c.creator = w.address
          AND c.protocol = 'in_process'
          AND c.chain_id = 8453
      ),
      artist_moments AS MATERIALIZED (
        SELECT ac.artist_id, m.id, m.channel
        FROM active_collections ac
        INNER JOIN public.in_process_moments m ON m.collection = ac.collection_id
      ),
      airdrop_counts AS (
        SELECT am.artist_id, SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
        FROM artist_moments am
        CROSS JOIN LATERAL (
          SELECT COUNT(*) AS cnt
          FROM public.in_process_transfers t
          WHERE t.moment = am.id
            AND t.value IS NULL
            AND t.recipient NOT IN (
              SELECT w3.address FROM public.in_process_wallets w3 WHERE w3.artist = am.artist_id
            )
        ) airdrop_count
        GROUP BY am.artist_id
      ),
      artist_wallets AS (
        SELECT w.artist AS artist_id,
          JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
        FROM public.in_process_wallets w
        WHERE w.artist IN (SELECT DISTINCT ac.artist_id FROM active_collections ac)
        GROUP BY w.artist
      ),
      stats AS (
        SELECT
          aa.artist_id,
          aa.username,
          aw.wallets,
          COUNT(am.id)                                                                 AS created_count,
          COALESCE(ac.airdropped_count, 0)                                             AS airdropped_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                          AS telegram_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)         AS web_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'api')                               AS api_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'sms')                               AS sms_count
        FROM active_artists aa
        INNER JOIN artist_moments am ON am.artist_id = aa.artist_id
        INNER JOIN artist_wallets  aw ON aw.artist_id = aa.artist_id
        LEFT  JOIN airdrop_counts  ac ON ac.artist_id = aa.artist_id
        GROUP BY aa.artist_id, aa.username, aw.wallets, ac.airdropped_count
      )
      SELECT
        s.artist_id::TEXT, s.username, s.wallets,
        s.created_count, s.airdropped_count,
        s.telegram_count, s.web_count, s.api_count, s.sms_count,
        COUNT(*) OVER () AS total_count
      FROM stats s
      ORDER BY
        CASE WHEN v_sort_order = 'asc'  THEN s.airdropped_count END ASC  NULLS LAST,
        CASE WHEN v_sort_order = 'desc' THEN s.airdropped_count END DESC NULLS LAST
      LIMIT p_limit OFFSET (p_page - 1) * p_limit;

    ELSE
      RETURN QUERY
      WITH active_artists AS MATERIALIZED (
        SELECT a.id AS artist_id, a.username
        FROM public.in_process_artists a
        WHERE a.username IS NOT NULL AND a.username != ''
          AND (
            p_artist IS NULL
            OR a.id IN (
              SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
              UNION
              SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
            )
          )
      ),
      active_collections AS MATERIALIZED (
        SELECT c.id AS collection_id, aa.artist_id
        FROM active_artists aa
        INNER JOIN public.in_process_wallets w  ON w.artist = aa.artist_id
        INNER JOIN public.in_process_collections c ON c.creator = w.address
          AND c.protocol = 'in_process'
          AND c.chain_id = 8453
      ),
      artist_moments AS MATERIALIZED (
        SELECT ac.artist_id, m.id, m.channel
        FROM active_collections ac
        INNER JOIN public.in_process_moments m ON m.collection = ac.collection_id
      ),
      artist_wallets AS (
        SELECT w.artist AS artist_id,
          JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
        FROM public.in_process_wallets w
        WHERE w.artist IN (SELECT DISTINCT ac.artist_id FROM active_collections ac)
        GROUP BY w.artist
      ),
      stats_base AS (
        SELECT
          aa.artist_id,
          aa.username,
          aw.wallets,
          COUNT(am.id)                                                                 AS created_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                          AS telegram_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)         AS web_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'api')                               AS api_count,
          COUNT(am.id) FILTER (WHERE am.channel = 'sms')                               AS sms_count
        FROM active_artists aa
        INNER JOIN artist_moments am ON am.artist_id = aa.artist_id
        INNER JOIN artist_wallets  aw ON aw.artist_id = aa.artist_id
        GROUP BY aa.artist_id, aa.username, aw.wallets
      ),
      paged AS (
        SELECT sb.artist_id, sb.username, sb.wallets, sb.created_count,
          sb.telegram_count, sb.web_count, sb.api_count, sb.sms_count,
          COUNT(*) OVER () AS total_count
        FROM stats_base sb
        ORDER BY
          CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
            WHEN 'created_count'  THEN sb.created_count
            WHEN 'telegram_count' THEN sb.telegram_count
            WHEN 'web_count'      THEN sb.web_count
            WHEN 'api_count'      THEN sb.api_count
            WHEN 'sms_count'      THEN sb.sms_count
          END END ASC,
          CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
            WHEN 'created_count'  THEN sb.created_count
            WHEN 'telegram_count' THEN sb.telegram_count
            WHEN 'web_count'      THEN sb.web_count
            WHEN 'api_count'      THEN sb.api_count
            WHEN 'sms_count'      THEN sb.sms_count
          END END DESC
        LIMIT p_limit OFFSET (p_page - 1) * p_limit
      ),
      airdrop_counts AS (
        SELECT am.artist_id, SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
        FROM artist_moments am
        INNER JOIN paged p ON p.artist_id = am.artist_id
        CROSS JOIN LATERAL (
          SELECT COUNT(*) AS cnt
          FROM public.in_process_transfers t
          WHERE t.moment = am.id
            AND t.value IS NULL
            AND t.recipient NOT IN (
              SELECT w3.address FROM public.in_process_wallets w3 WHERE w3.artist = am.artist_id
            )
        ) airdrop_count
        GROUP BY am.artist_id
      )
      SELECT
        p.artist_id::TEXT, p.username, p.wallets,
        p.created_count, COALESCE(ac.airdropped_count, 0) AS airdropped_count,
        p.telegram_count, p.web_count, p.api_count, p.sms_count, p.total_count
      FROM paged p
      LEFT JOIN airdrop_counts ac ON ac.artist_id = p.artist_id
      ORDER BY
        CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
          WHEN 'created_count'  THEN p.created_count
          WHEN 'telegram_count' THEN p.telegram_count
          WHEN 'web_count'      THEN p.web_count
          WHEN 'api_count'      THEN p.api_count
          WHEN 'sms_count'      THEN p.sms_count
        END END ASC,
        CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
          WHEN 'created_count'  THEN p.created_count
          WHEN 'telegram_count' THEN p.telegram_count
          WHEN 'web_count'      THEN p.web_count
          WHEN 'api_count'      THEN p.api_count
          WHEN 'sms_count'      THEN p.sms_count
        END END DESC;
    END IF;
    RETURN;
  END IF;

  -- ── period=day/week/month: unchanged ─────────────────────────────────────────
  v_interval := CASE p_period
    WHEN 'day'   THEN INTERVAL '1 day'
    WHEN 'week'  THEN INTERVAL '7 days'
    WHEN 'month' THEN INTERVAL '30 days'
    ELSE               INTERVAL '7 days'
  END;

  IF v_sort_by = 'airdropped_count' THEN
    RETURN QUERY
    WITH artist_moments AS MATERIALIZED (
      SELECT w.artist AS artist_id, m.id, m.channel
      FROM public.in_process_moments m
      INNER JOIN public.in_process_collections c ON c.id = m.collection
      INNER JOIN public.in_process_wallets w     ON w.address = c.creator
      WHERE c.protocol = 'in_process'
        AND c.chain_id = 8453
        AND m.created_at >= NOW() - v_interval
        AND (
          p_artist IS NULL
          OR w.artist IN (
            SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
            UNION
            SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    airdrop_counts AS (
      SELECT am.artist_id, SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
      FROM artist_moments am
      CROSS JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM public.in_process_transfers t
        WHERE t.moment = am.id
          AND t.value IS NULL
          AND t.recipient NOT IN (
            SELECT w3.address FROM public.in_process_wallets w3 WHERE w3.artist = am.artist_id
          )
      ) airdrop_count
      GROUP BY am.artist_id
    ),
    artist_wallets AS (
      SELECT w.artist AS artist_id,
        JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
      FROM public.in_process_wallets w
      WHERE w.artist IN (SELECT DISTINCT am.artist_id FROM artist_moments am)
      GROUP BY w.artist
    ),
    stats AS (
      SELECT
        a.id                                                                         AS artist_id,
        a.username,
        aw.wallets,
        COUNT(am.id)                                                                 AS created_count,
        COALESCE(ac.airdropped_count, 0)                                             AS airdropped_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                          AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)         AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                               AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                               AS sms_count
      FROM public.in_process_artists a
      INNER JOIN artist_moments am ON am.artist_id = a.id
      INNER JOIN artist_wallets  aw ON aw.artist_id = a.id
      LEFT  JOIN airdrop_counts  ac ON ac.artist_id = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
      GROUP BY a.id, a.username, aw.wallets, ac.airdropped_count
    )
    SELECT
      s.artist_id::TEXT, s.username, s.wallets,
      s.created_count, s.airdropped_count,
      s.telegram_count, s.web_count, s.api_count, s.sms_count,
      COUNT(*) OVER () AS total_count
    FROM stats s
    ORDER BY
      CASE WHEN v_sort_order = 'asc'  THEN s.airdropped_count END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN s.airdropped_count END DESC NULLS LAST
    LIMIT p_limit OFFSET (p_page - 1) * p_limit;

  ELSE
    RETURN QUERY
    WITH artist_moments AS MATERIALIZED (
      SELECT w.artist AS artist_id, m.id, m.channel
      FROM public.in_process_moments m
      INNER JOIN public.in_process_collections c ON c.id = m.collection
      INNER JOIN public.in_process_wallets w     ON w.address = c.creator
      WHERE c.protocol = 'in_process'
        AND c.chain_id = 8453
        AND m.created_at >= NOW() - v_interval
        AND (
          p_artist IS NULL
          OR w.artist IN (
            SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
            UNION
            SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    artist_wallets AS (
      SELECT w.artist AS artist_id,
        JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
      FROM public.in_process_wallets w
      WHERE w.artist IN (SELECT DISTINCT am.artist_id FROM artist_moments am)
      GROUP BY w.artist
    ),
    stats_base AS (
      SELECT
        a.id                                                                         AS artist_id,
        a.username,
        aw.wallets,
        COUNT(am.id)                                                                 AS created_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                          AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)         AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                               AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                               AS sms_count
      FROM public.in_process_artists a
      INNER JOIN artist_moments am ON am.artist_id = a.id
      INNER JOIN artist_wallets  aw ON aw.artist_id = a.id
      WHERE a.username IS NOT NULL AND a.username != ''
      GROUP BY a.id, a.username, aw.wallets
    ),
    paged AS (
      SELECT sb.artist_id, sb.username, sb.wallets, sb.created_count,
        sb.telegram_count, sb.web_count, sb.api_count, sb.sms_count,
        COUNT(*) OVER () AS total_count
      FROM stats_base sb
      ORDER BY
        CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
          WHEN 'created_count'  THEN sb.created_count
          WHEN 'telegram_count' THEN sb.telegram_count
          WHEN 'web_count'      THEN sb.web_count
          WHEN 'api_count'      THEN sb.api_count
          WHEN 'sms_count'      THEN sb.sms_count
        END END ASC,
        CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
          WHEN 'created_count'  THEN sb.created_count
          WHEN 'telegram_count' THEN sb.telegram_count
          WHEN 'web_count'      THEN sb.web_count
          WHEN 'api_count'      THEN sb.api_count
          WHEN 'sms_count'      THEN sb.sms_count
        END END DESC
      LIMIT p_limit OFFSET (p_page - 1) * p_limit
    ),
    airdrop_counts AS (
      SELECT am.artist_id, SUM(airdrop_count.cnt)::BIGINT AS airdropped_count
      FROM artist_moments am
      INNER JOIN paged p ON p.artist_id = am.artist_id
      CROSS JOIN LATERAL (
        SELECT COUNT(*) AS cnt
        FROM public.in_process_transfers t
        WHERE t.moment = am.id
          AND t.value IS NULL
          AND t.recipient NOT IN (
            SELECT w3.address FROM public.in_process_wallets w3 WHERE w3.artist = am.artist_id
          )
      ) airdrop_count
      GROUP BY am.artist_id
    )
    SELECT
      p.artist_id::TEXT, p.username, p.wallets,
      p.created_count, COALESCE(ac.airdropped_count, 0) AS airdropped_count,
      p.telegram_count, p.web_count, p.api_count, p.sms_count, p.total_count
    FROM paged p
    LEFT JOIN airdrop_counts ac ON ac.artist_id = p.artist_id
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
        WHEN 'created_count'  THEN p.created_count
        WHEN 'telegram_count' THEN p.telegram_count
        WHEN 'web_count'      THEN p.web_count
        WHEN 'api_count'      THEN p.api_count
        WHEN 'sms_count'      THEN p.sms_count
      END END ASC,
      CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
        WHEN 'created_count'  THEN p.created_count
        WHEN 'telegram_count' THEN p.telegram_count
        WHEN 'web_count'      THEN p.web_count
        WHEN 'api_count'      THEN p.api_count
        WHEN 'sms_count'      THEN p.sms_count
      END END DESC;
  END IF;
END;
$$;

-- ── 2. get_collectors_stats ───────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_collectors_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'collected_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  artist_id TEXT,
  username TEXT,
  wallets JSONB,
  collected_count BIGINT,
  eth_spent TEXT,
  usdc_spent TEXT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT     := LOWER(COALESCE(p_sort_by,    'collected_count'));
  v_sort_order TEXT     := LOWER(COALESCE(p_sort_order, 'desc'));
  v_usdc_addr  TEXT     := '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913';
  v_eth_addr   TEXT     := '0x0000000000000000000000000000000000000000';
  v_interval   INTERVAL;
BEGIN
  IF v_sort_by NOT IN ('collected_count','eth_spent','usdc_spent') THEN
    v_sort_by := 'collected_count';
  END IF;
  IF v_sort_order NOT IN ('asc','desc') THEN
    v_sort_order := 'desc';
  END IF;

  -- ── period='all': start from active_artists (3,328) → wallets → paid transfers
  IF p_period IS NULL OR p_period = 'all' THEN
    RETURN QUERY
    WITH active_artists AS MATERIALIZED (
      SELECT a.id AS artist_id, a.username
      FROM public.in_process_artists a
      WHERE a.username IS NOT NULL AND a.username != ''
        AND (
          p_artist IS NULL
          OR a.id IN (
            SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
            UNION
            SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    paid_transfers AS MATERIALIZED (
      SELECT aa.artist_id, aa.username, t.value, t.currency
      FROM active_artists aa
      INNER JOIN public.in_process_wallets w  ON w.artist = aa.artist_id
      INNER JOIN public.in_process_transfers t ON t.recipient = w.address
        AND t.value IS NOT NULL
      INNER JOIN public.in_process_moments m  ON m.id = t.moment
      INNER JOIN public.in_process_collections c ON c.id = m.collection
        AND c.protocol = 'in_process'
        AND c.chain_id = 8453
    ),
    artist_wallets AS (
      SELECT w.artist AS artist_id,
        JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
      FROM public.in_process_wallets w
      WHERE w.artist IN (SELECT DISTINCT pt.artist_id FROM paid_transfers pt)
      GROUP BY w.artist
    ),
    stats AS (
      SELECT
        pt.artist_id, pt.username, aw.wallets,
        COUNT(*)                                                                       AS collected_count,
        COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_eth_addr),  0)  AS eth_spent,
        COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_usdc_addr), 0)  AS usdc_spent
      FROM paid_transfers pt
      INNER JOIN artist_wallets aw ON aw.artist_id = pt.artist_id
      GROUP BY pt.artist_id, pt.username, aw.wallets
    ),
    paged AS (
      SELECT s.artist_id, s.username, s.wallets, s.collected_count, s.eth_spent, s.usdc_spent,
        COUNT(*) OVER () AS total_count
      FROM stats s
      ORDER BY
        CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
          WHEN 'collected_count' THEN s.collected_count::NUMERIC
          WHEN 'eth_spent'       THEN s.eth_spent
          WHEN 'usdc_spent'      THEN s.usdc_spent
        END END ASC  NULLS LAST,
        CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
          WHEN 'collected_count' THEN s.collected_count::NUMERIC
          WHEN 'eth_spent'       THEN s.eth_spent
          WHEN 'usdc_spent'      THEN s.usdc_spent
        END END DESC NULLS LAST,
        s.artist_id ASC
      LIMIT p_limit OFFSET (p_page - 1) * p_limit
    )
    SELECT
      p.artist_id::TEXT, p.username, p.wallets, p.collected_count,
      TRIM(TRAILING '.' FROM to_char(p.eth_spent,  'FM999999999999990.999999999999999999')),
      TRIM(TRAILING '.' FROM to_char(p.usdc_spent, 'FM999999999999990.999999')),
      p.total_count
    FROM paged p
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
        WHEN 'collected_count' THEN p.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN p.eth_spent
        WHEN 'usdc_spent'      THEN p.usdc_spent
      END END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
        WHEN 'collected_count' THEN p.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN p.eth_spent
        WHEN 'usdc_spent'      THEN p.usdc_spent
      END END DESC NULLS LAST,
      p.artist_id ASC;
    RETURN;
  END IF;

  -- ── period=day/week/month: unchanged ─────────────────────────────────────────
  v_interval := CASE p_period
    WHEN 'day'   THEN INTERVAL '1 day'
    WHEN 'week'  THEN INTERVAL '7 days'
    WHEN 'month' THEN INTERVAL '30 days'
    ELSE               INTERVAL '7 days'
  END;

  RETURN QUERY
  WITH paid_transfers AS MATERIALIZED (
    SELECT w.artist AS artist_id, a.username, t.value, t.currency
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m     ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w     ON w.address = t.recipient
    INNER JOIN public.in_process_artists a     ON a.id = w.artist
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND a.username IS NOT NULL AND a.username != ''
      AND t.transferred_at >= NOW() - v_interval
      AND (
        p_artist IS NULL
        OR w.artist IN (
          SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
        )
        OR w.artist IN (
          SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  artist_wallets AS (
    SELECT w.artist AS artist_id,
      JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
    FROM public.in_process_wallets w
    WHERE w.artist IN (SELECT DISTINCT pt.artist_id FROM paid_transfers pt)
    GROUP BY w.artist
  ),
  stats AS (
    SELECT
      pt.artist_id, pt.username, aw.wallets,
      COUNT(*)                                                                       AS collected_count,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_eth_addr),  0)  AS eth_spent,
      COALESCE(SUM(pt.value::NUMERIC) FILTER (WHERE pt.currency = v_usdc_addr), 0)  AS usdc_spent
    FROM paid_transfers pt
    INNER JOIN artist_wallets aw ON aw.artist_id = pt.artist_id
    GROUP BY pt.artist_id, pt.username, aw.wallets
  ),
  paged AS (
    SELECT s.artist_id, s.username, s.wallets, s.collected_count, s.eth_spent, s.usdc_spent,
      COUNT(*) OVER () AS total_count
    FROM stats s
    ORDER BY
      CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
        WHEN 'collected_count' THEN s.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN s.eth_spent
        WHEN 'usdc_spent'      THEN s.usdc_spent
      END END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
        WHEN 'collected_count' THEN s.collected_count::NUMERIC
        WHEN 'eth_spent'       THEN s.eth_spent
        WHEN 'usdc_spent'      THEN s.usdc_spent
      END END DESC NULLS LAST,
      s.artist_id ASC
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT
    p.artist_id::TEXT, p.username, p.wallets, p.collected_count,
    TRIM(TRAILING '.' FROM to_char(p.eth_spent,  'FM999999999999990.999999999999999999')),
    TRIM(TRAILING '.' FROM to_char(p.usdc_spent, 'FM999999999999990.999999')),
    p.total_count
  FROM paged p
  ORDER BY
    CASE WHEN v_sort_order = 'asc' THEN CASE v_sort_by
      WHEN 'collected_count' THEN p.collected_count::NUMERIC
      WHEN 'eth_spent'       THEN p.eth_spent
      WHEN 'usdc_spent'      THEN p.usdc_spent
    END END ASC  NULLS LAST,
    CASE WHEN v_sort_order = 'desc' THEN CASE v_sort_by
      WHEN 'collected_count' THEN p.collected_count::NUMERIC
      WHEN 'eth_spent'       THEN p.eth_spent
      WHEN 'usdc_spent'      THEN p.usdc_spent
    END END DESC NULLS LAST,
    p.artist_id ASC;
END;
$$;

-- ── 3. get_artists_collectors_stats ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_artists_collectors_stats (
  p_period TEXT DEFAULT 'all',
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_artist TEXT DEFAULT NULL,
  p_sort_by TEXT DEFAULT 'total_created_count',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  artist_id TEXT,
  username TEXT,
  wallets JSONB,
  total_created_count BIGINT,
  total_collected_count BIGINT,
  total_count BIGINT
) language plpgsql stable AS $$
DECLARE
  v_sort_by    TEXT     := LOWER(COALESCE(p_sort_by,    'total_created_count'));
  v_sort_order TEXT     := LOWER(COALESCE(p_sort_order, 'desc'));
  v_interval   INTERVAL;
BEGIN
  IF v_sort_by NOT IN ('total_created_count','total_collected_count') THEN
    v_sort_by := 'total_created_count';
  END IF;
  IF v_sort_order NOT IN ('asc','desc') THEN
    v_sort_order := 'desc';
  END IF;

  -- ── period='all': start from active_artists (3,328) → collections / wallets ─
  IF p_period IS NULL OR p_period = 'all' THEN
    RETURN QUERY
    WITH active_artists AS MATERIALIZED (
      SELECT a.id AS artist_id, a.username
      FROM public.in_process_artists a
      WHERE a.username IS NOT NULL AND a.username != ''
        AND (
          p_artist IS NULL
          OR a.id IN (
            SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
            UNION
            SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    active_collections AS MATERIALIZED (
      SELECT c.id AS collection_id, aa.artist_id
      FROM active_artists aa
      INNER JOIN public.in_process_wallets w  ON w.artist = aa.artist_id
      INNER JOIN public.in_process_collections c ON c.creator = w.address
        AND c.protocol = 'in_process'
        AND c.chain_id = 8453
    ),
    created_counts AS (
      SELECT ac.artist_id, COUNT(*) AS created_count
      FROM active_collections ac
      INNER JOIN public.in_process_moments m ON m.collection = ac.collection_id
      GROUP BY ac.artist_id
    ),
    collected_counts AS (
      SELECT aa.artist_id, COUNT(*) AS collected_count
      FROM active_artists aa
      INNER JOIN public.in_process_wallets w  ON w.artist = aa.artist_id
      INNER JOIN public.in_process_transfers t ON t.recipient = w.address
        AND t.value IS NOT NULL
      INNER JOIN public.in_process_moments m  ON m.id = t.moment
      INNER JOIN public.in_process_collections c ON c.id = m.collection
        AND c.protocol = 'in_process'
        AND c.chain_id = 8453
      GROUP BY aa.artist_id
    ),
    artist_wallets AS (
      SELECT w.artist AS artist_id,
        JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
      FROM public.in_process_wallets w
      WHERE w.artist IN (SELECT DISTINCT ac.artist_id FROM active_collections ac)
      GROUP BY w.artist
    ),
    stats AS (
      SELECT aa.artist_id::TEXT AS artist_id, aa.username, aw.wallets,
        cc.created_count AS total_created_count,
        COALESCE(col.collected_count, 0) AS total_collected_count
      FROM active_artists aa
      INNER JOIN created_counts   cc  ON cc.artist_id  = aa.artist_id
      INNER JOIN collected_counts col ON col.artist_id = aa.artist_id
      INNER JOIN artist_wallets   aw  ON aw.artist_id  = aa.artist_id
    ),
    with_sort AS (
      SELECT s.artist_id, s.username, s.wallets, s.total_created_count, s.total_collected_count,
        COUNT(*) OVER () AS total_count,
        CASE v_sort_by
          WHEN 'total_created_count'   THEN s.total_created_count
          WHEN 'total_collected_count' THEN s.total_collected_count
        END AS sort_key
      FROM stats s
    ),
    paged AS (
      SELECT * FROM with_sort
      ORDER BY
        CASE WHEN v_sort_order = 'asc'  THEN sort_key END ASC  NULLS LAST,
        CASE WHEN v_sort_order = 'desc' THEN sort_key END DESC NULLS LAST,
        artist_id ASC
      LIMIT p_limit OFFSET (p_page - 1) * p_limit
    )
    SELECT p.artist_id, p.username, p.wallets, p.total_created_count, p.total_collected_count, p.total_count
    FROM paged p
    ORDER BY
      CASE WHEN v_sort_order = 'asc'  THEN p.sort_key END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN p.sort_key END DESC NULLS LAST,
      p.artist_id ASC;
    RETURN;
  END IF;

  -- ── period=day/week/month: unchanged ─────────────────────────────────────────
  v_interval := CASE p_period
    WHEN 'day'   THEN INTERVAL '1 day'
    WHEN 'week'  THEN INTERVAL '7 days'
    WHEN 'month' THEN INTERVAL '30 days'
    ELSE               INTERVAL '7 days'
  END;

  RETURN QUERY
  WITH artist_moments AS MATERIALIZED (
    SELECT w.artist AS artist_id, m.id AS moment_id
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w     ON w.address = c.creator
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND m.created_at >= NOW() - v_interval
      AND (
        p_artist IS NULL
        OR w.artist IN (
          SELECT w2.artist FROM public.in_process_wallets w2 WHERE w2.address = LOWER(p_artist)
        )
        OR w.artist IN (
          SELECT a2.id FROM public.in_process_artists a2 WHERE a2.username ILIKE '%' || p_artist || '%'
        )
      )
  ),
  created_counts AS (
    SELECT am.artist_id, COUNT(*) AS created_count FROM artist_moments am GROUP BY am.artist_id
  ),
  collected_counts AS (
    SELECT w.artist AS artist_id, COUNT(*) AS collected_count
    FROM public.in_process_transfers t
    INNER JOIN public.in_process_moments m     ON m.id = t.moment
    INNER JOIN public.in_process_collections c ON c.id = m.collection
    INNER JOIN public.in_process_wallets w     ON w.address = t.recipient
    WHERE c.protocol = 'in_process'
      AND c.chain_id = 8453
      AND t.value IS NOT NULL
      AND t.transferred_at >= NOW() - v_interval
    GROUP BY w.artist
  ),
  artist_wallets AS (
    SELECT w.artist AS artist_id,
      JSONB_AGG(JSONB_BUILD_OBJECT('address', w.address, 'type', w.type) ORDER BY w.address) AS wallets
    FROM public.in_process_wallets w
    WHERE w.artist IN (SELECT DISTINCT am.artist_id FROM artist_moments am)
    GROUP BY w.artist
  ),
  stats AS (
    SELECT a.id::TEXT AS artist_id, a.username, aw.wallets,
      cc.created_count AS total_created_count, col.collected_count AS total_collected_count
    FROM public.in_process_artists a
    INNER JOIN created_counts   cc  ON cc.artist_id  = a.id
    INNER JOIN collected_counts col ON col.artist_id = a.id
    INNER JOIN artist_wallets   aw  ON aw.artist_id  = a.id
    WHERE a.username IS NOT NULL AND a.username != ''
  ),
  with_sort AS (
    SELECT s.artist_id, s.username, s.wallets, s.total_created_count, s.total_collected_count,
      COUNT(*) OVER () AS total_count,
      CASE v_sort_by
        WHEN 'total_created_count'   THEN s.total_created_count
        WHEN 'total_collected_count' THEN s.total_collected_count
      END AS sort_key
    FROM stats s
  ),
  paged AS (
    SELECT * FROM with_sort
    ORDER BY
      CASE WHEN v_sort_order = 'asc'  THEN sort_key END ASC  NULLS LAST,
      CASE WHEN v_sort_order = 'desc' THEN sort_key END DESC NULLS LAST,
      artist_id ASC
    LIMIT p_limit OFFSET (p_page - 1) * p_limit
  )
  SELECT p.artist_id, p.username, p.wallets, p.total_created_count, p.total_collected_count, p.total_count
  FROM paged p
  ORDER BY
    CASE WHEN v_sort_order = 'asc'  THEN p.sort_key END ASC  NULLS LAST,
    CASE WHEN v_sort_order = 'desc' THEN p.sort_key END DESC NULLS LAST,
    p.artist_id ASC;
END;
$$;
