-- PR6 final step: drop in_process_artists.address and update all RPCs that
-- joined through it. After migration 017, every FK that pointed at
-- in_process_artists(address) was repointed to in_process_wallets(address),
-- so the canonical address lives in in_process_wallets, not on the artist row.
-- ---------------------------------------------------------------------------
-- 1. get_active_artists_stats
--    Replace `FROM in_process_artists a JOIN artist_moments ON a.address`
--    with a wallet-based join so we can still look up addresses after the
--    column is gone.
-- ---------------------------------------------------------------------------
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
            SELECT w2.address
            FROM public.in_process_wallets w2
            INNER JOIN public.in_process_artists a2 ON a2.id = w2.artist
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
        w.address,
        a.username,
        COUNT(am.id)                                                          AS created_count,
        COALESCE(ac.airdropped_count, 0)                                      AS airdropped_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                   AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)  AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                        AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                        AS sms_count
      FROM public.in_process_wallets w
      INNER JOIN public.in_process_artists a ON a.id = w.artist
      INNER JOIN artist_moments am ON am.artist_address = w.address
      LEFT JOIN airdrop_counts ac ON ac.artist_address = w.address
      WHERE a.username IS NOT NULL
        AND a.username != ''
      GROUP BY w.address, a.username, ac.airdropped_count
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
            SELECT w2.address
            FROM public.in_process_wallets w2
            INNER JOIN public.in_process_artists a2 ON a2.id = w2.artist
            WHERE a2.username ILIKE '%' || p_artist || '%'
          )
        )
    ),
    stats_base AS (
      SELECT
        w.address,
        a.username,
        COUNT(am.id)                                                          AS created_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'telegram')                   AS telegram_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'web' OR am.channel IS NULL)  AS web_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'api')                        AS api_count,
        COUNT(am.id) FILTER (WHERE am.channel = 'sms')                        AS sms_count
      FROM public.in_process_wallets w
      INNER JOIN public.in_process_artists a ON a.id = w.artist
      INNER JOIN artist_moments am ON am.artist_address = w.address
      WHERE a.username IS NOT NULL
        AND a.username != ''
      GROUP BY w.address, a.username
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

-- ---------------------------------------------------------------------------
-- 2. get_arweave_uploads (aggregate per-artist view)
--    Route the in_process_artists join through in_process_wallets; return
--    u.artist_address directly instead of a.address (same value).
-- ---------------------------------------------------------------------------
DROP FUNCTION if EXISTS public.get_arweave_uploads (TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_arweave_uploads (
  p_artist TEXT DEFAULT NULL,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_sort_by TEXT DEFAULT 'usdc_cost',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  winc_cost TEXT,
  usdc_cost NUMERIC,
  artist_username TEXT,
  artist_address TEXT,
  total_count BIGINT,
  total_usdc_cost NUMERIC
) language sql stable AS $$
  WITH filtered AS (
    SELECT
      u.artist_address,
      a.username AS artist_username,
      u.winc_cost,
      u.usdc_cost
    FROM in_process_arweave_uploads u
    LEFT JOIN in_process_wallets w ON w.address = u.artist_address
    LEFT JOIN in_process_artists a ON a.id = w.artist
    WHERE
      (p_artist IS NULL OR
        CASE
          WHEN p_artist ~ '^0x[0-9a-fA-F]{40}$' THEN u.artist_address = lower(p_artist)
          ELSE a.username ILIKE p_artist
        END)
      AND (p_from IS NULL OR u.created_at >= p_from)
  ),
  grouped AS (
    SELECT
      f.artist_address,
      f.artist_username,
      COALESCE(
        SUM(COALESCE(NULLIF(trim(f.winc_cost), '')::NUMERIC, 0)),
        0
      ) AS winc_sum,
      COALESCE(SUM(f.usdc_cost), 0) AS usdc_sum
    FROM filtered f
    GROUP BY f.artist_address, f.artist_username
  ),
  with_totals AS (
    SELECT
      g.artist_address,
      g.artist_username,
      g.winc_sum,
      g.usdc_sum,
      COUNT(*) OVER ()::BIGINT AS total_count,
      COALESCE(SUM(g.usdc_sum) OVER (), 0) AS total_usdc_cost
    FROM grouped g
  )
  SELECT
    ROUND(w.winc_sum)::BIGINT::TEXT,
    w.usdc_sum,
    w.artist_username,
    w.artist_address,
    w.total_count,
    w.total_usdc_cost
  FROM with_totals w
  ORDER BY
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'asc' THEN w.usdc_sum END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'desc' THEN w.usdc_sum END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'asc' THEN w.winc_sum END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'desc' THEN w.winc_sum END DESC NULLS LAST,
    CASE
      WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost')
        AND p_sort_order = 'asc'
      THEN w.usdc_sum
    END ASC NULLS LAST,
    CASE
      WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost')
        AND p_sort_order = 'desc'
      THEN w.usdc_sum
    END DESC NULLS LAST
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;

-- ---------------------------------------------------------------------------
-- 3. get_artist_arweave_uploads (per-upload listing)
-- ---------------------------------------------------------------------------
DROP FUNCTION if EXISTS public.get_artist_arweave_uploads (TEXT, TIMESTAMPTZ, INTEGER, INTEGER, TEXT, TEXT);

CREATE OR REPLACE FUNCTION public.get_artist_arweave_uploads (
  p_artist TEXT DEFAULT NULL,
  p_from TIMESTAMPTZ DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1,
  p_sort_by TEXT DEFAULT 'created_at',
  p_sort_order TEXT DEFAULT 'desc'
) returns TABLE (
  id UUID,
  arweave_uri TEXT,
  winc_cost TEXT,
  usdc_cost NUMERIC,
  file_size_bytes BIGINT,
  content_type TEXT,
  created_at TIMESTAMPTZ,
  total_count BIGINT
) language sql stable AS $$
  SELECT
    u.id,
    u.arweave_uri,
    u.winc_cost,
    u.usdc_cost,
    u.file_size_bytes,
    u.content_type,
    u.created_at,
    COUNT(*) OVER ()::BIGINT
  FROM in_process_arweave_uploads u
  LEFT JOIN in_process_wallets w ON w.address = u.artist_address
  LEFT JOIN in_process_artists a ON a.id = w.artist
  WHERE
    (p_artist IS NULL OR
      CASE
        WHEN p_artist ~ '^0x[0-9a-fA-F]{40}$' THEN u.artist_address = lower(p_artist)
        ELSE lower(trim(a.username)) = lower(trim(p_artist))
      END)
    AND (p_from IS NULL OR u.created_at >= p_from)
  ORDER BY
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'asc' THEN u.usdc_cost END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'usdc_cost' AND p_sort_order = 'desc' THEN u.usdc_cost END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'asc' THEN COALESCE(NULLIF(trim(u.winc_cost), '')::NUMERIC, 0) END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'winc_cost' AND p_sort_order = 'desc' THEN COALESCE(NULLIF(trim(u.winc_cost), '')::NUMERIC, 0) END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'asc' THEN u.file_size_bytes::NUMERIC END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'size' AND p_sort_order = 'desc' THEN u.file_size_bytes::NUMERIC END DESC NULLS LAST,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'asc' THEN u.created_at END ASC NULLS LAST,
    CASE WHEN p_sort_by = 'created_at' AND p_sort_order = 'desc' THEN u.created_at END DESC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size', 'created_at') AND p_sort_order = 'asc' THEN u.created_at END ASC NULLS LAST,
    CASE WHEN p_sort_by NOT IN ('usdc_cost', 'winc_cost', 'size', 'created_at') AND p_sort_order = 'desc' THEN u.created_at END DESC NULLS LAST
  LIMIT p_limit OFFSET (p_page - 1) * p_limit;
$$;

-- ---------------------------------------------------------------------------
-- 4. get_collections
--    Replace `LEFT JOIN in_process_artists art ON art.address = c.creator`
--    with a two-hop join through in_process_wallets.
-- ---------------------------------------------------------------------------
DROP FUNCTION if EXISTS public.get_artist_collections (TEXT, INT, INT, INT);

CREATE OR REPLACE FUNCTION public.get_collections (
  p_artist TEXT DEFAULT NULL,
  p_chainid INT DEFAULT NULL,
  p_addresses TEXT[] DEFAULT NULL,
  p_limit INT DEFAULT 20,
  p_page INT DEFAULT 1
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit    int     := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page    int     := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val      int     := (clamped_page - 1) * capped_limit;
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
    LEFT JOIN in_process_wallets w_c ON w_c.address = c.creator
    LEFT JOIN in_process_artists art ON art.id = w_c.artist
    WHERE
      (p_addresses IS NULL OR c.address = ANY(p_addresses))
      AND (p_artist  IS NULL OR c.creator  = LOWER(p_artist))
      AND (p_chainid IS NULL OR c.chain_id = p_chainid)
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

-- ---------------------------------------------------------------------------
-- 5. get_airdrop_transfers
--    Replace `JOIN in_process_artists creator ON creator.address = c.creator`
--    and `JOIN in_process_artists collector ON collector.address = ft.recipient`
--    with two-hop joins through in_process_wallets.
-- ---------------------------------------------------------------------------
DROP FUNCTION if EXISTS public.get_airdrop_transfers (TEXT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.get_airdrop_transfers (
  p_artist TEXT DEFAULT NULL,
  p_collector TEXT DEFAULT NULL,
  p_chain_id NUMERIC DEFAULT NULL,
  p_content_type TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
) returns TABLE (transfers JSONB, total_count BIGINT) language sql stable AS $function$
  WITH filtered_collections AS (
    SELECT c.id
    FROM public.in_process_collections c
    WHERE c.protocol = 'in_process'
      AND (p_chain_id IS NULL OR c.chain_id = p_chain_id)
      AND (p_artist IS NULL OR c.creator = lower(p_artist))
      AND (p_collector IS NULL OR c.creator <> lower(p_collector))
  ),
  filtered_moments AS (
    SELECT m.id
    FROM public.in_process_moments m
    JOIN filtered_collections fc ON fc.id = m.collection
  ),
  filtered_transfers AS (
    SELECT
      t.id,
      t.moment,
      t.recipient,
      t.quantity,
      t.currency,
      t.value,
      t.transaction_hash,
      t.transferred_at
    FROM public.in_process_transfers t
    JOIN filtered_moments fm ON fm.id = t.moment
    WHERE t.value IS NULL
      AND (p_artist IS NULL OR t.recipient <> lower(p_artist))
      AND (p_collector IS NULL OR t.recipient = lower(p_collector))
  ),
  filtered_with_joins AS (
    SELECT
      ft.id,
      ft.transferred_at,
      jsonb_build_object(
        'id', ft.id,
        'quantity', ft.quantity,
        'currency', ft.currency,
        'value', ft.value,
        'transaction_hash', ft.transaction_hash,
        'transferred_at', ft.transferred_at,
        'collector', jsonb_build_object(
          'address', ft.recipient,
          'username', collector_artist.username
        ),
        'moment', jsonb_build_object(
          'token_id', m.token_id,
          'collection', jsonb_build_object(
            'address', c.address,
            'chain_id', c.chain_id,
            'protocol', c.protocol,
            'artist', jsonb_build_object(
              'address', c.creator,
              'username', creator_artist.username
            )
          ),
          'metadata', jsonb_build_object(
            'name', md.name,
            'description', md.description,
            'external_url', md.external_url,
            'image', md.image,
            'animation_url', md.animation_url,
            'content', md.content
          )
        )
      ) AS transfer
    FROM filtered_transfers ft
    JOIN public.in_process_moments m ON m.id = ft.moment
    JOIN public.in_process_collections c ON c.id = m.collection
    LEFT JOIN public.in_process_wallets w_creator ON w_creator.address = c.creator
    LEFT JOIN public.in_process_artists creator_artist ON creator_artist.id = w_creator.artist
    LEFT JOIN public.in_process_wallets w_collector ON w_collector.address = ft.recipient
    LEFT JOIN public.in_process_artists collector_artist ON collector_artist.id = w_collector.artist
    LEFT JOIN public.in_process_metadata md ON md.moment = m.id
    WHERE (
      p_content_type IS NULL
      OR lower(md.content->>'mime') LIKE '%' || lower(p_content_type) || '%'
    )
  ),
  counted AS (
    SELECT count(*)::bigint AS total_count
    FROM filtered_with_joins
  ),
  paged AS (
    SELECT transfer, transferred_at, id
    FROM filtered_with_joins
    ORDER BY transferred_at DESC, id DESC
    LIMIT p_limit
    OFFSET p_offset
  )
  SELECT
    COALESCE(
      jsonb_agg(p.transfer ORDER BY p.transferred_at DESC, p.id DESC),
      '[]'::jsonb
    ) AS transfers,
    c.total_count
  FROM counted c
  LEFT JOIN paged p ON true
  GROUP BY c.total_count;
$function$;

-- ---------------------------------------------------------------------------
-- 6. Drop in_process_artists.address column (address identity now lives in
--    in_process_wallets; all FKs were repointed in migration 017).
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_artists
DROP COLUMN IF EXISTS address;
