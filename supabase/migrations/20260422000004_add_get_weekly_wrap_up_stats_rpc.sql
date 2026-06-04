-- Fast pre-filter of artists that can receive a telegram wrap-up.
CREATE INDEX if NOT EXISTS idx_in_process_artists_qualified ON public.in_process_artists (address)
WHERE
  username IS NOT NULL
  AND username <> ''
  AND telegram_username IS NOT NULL
  AND telegram_username <> '';

-- Powers the LATERAL "latest telegram chat_id per artist" lookup.
CREATE INDEX if NOT EXISTS idx_in_process_message_metadata_telegram_artist ON public.in_process_message_metadata (artist_address, created_at DESC)
WHERE
  client = 'telegram'
  AND artist_address IS NOT NULL;

-- ── Function ────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.get_weekly_wrap_up_stats (p_days INTEGER DEFAULT 7) returns TABLE (
  username TEXT,
  chat_id TEXT,
  telegram_count INTEGER,
  web_count INTEGER,
  api_count INTEGER,
  sms_count INTEGER
) language sql stable AS $function$
  -- Artists qualifying for a telegram wrap-up (username + telegram_username set).
  WITH qualified_artists AS (
    SELECT address
    FROM public.in_process_artists
    WHERE username IS NOT NULL AND username <> ''
      AND telegram_username IS NOT NULL AND telegram_username <> ''
  ),
  -- In-process moments created in the last p_days by qualified artists.
  weekly_moments AS (
    SELECT m.id AS moment_id, c.creator AS artist_address
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON m.collection = c.id
    INNER JOIN qualified_artists qa           ON qa.address = c.creator
    WHERE m.created_at >= NOW() - make_interval(days => p_days)
      AND c.protocol = 'in_process'
      AND c.chain_id = 8453
  ),
  -- Deduped (moment, artist, client) tuples for each weekly moment's creation channel.
  moment_channels AS (
    SELECT DISTINCT
      wm.moment_id,
      wm.artist_address,
      mm.client
    FROM weekly_moments wm
    INNER JOIN public.in_process_message_moment mnm  ON mnm.moment = wm.moment_id
    INNER JOIN public.in_process_messages msg        ON msg.id = mnm.message
    INNER JOIN public.in_process_message_metadata mm ON mm.id = msg.metadata
  ),
  -- Per-artist channel counts (one row per artist with weekly activity).
  per_artist_counts AS (
    SELECT
      artist_address,
      COUNT(*) FILTER (WHERE client = 'telegram')::int AS telegram_count,
      COUNT(*) FILTER (WHERE client = 'web')::int      AS web_count,
      COUNT(*) FILTER (WHERE client = 'api')::int      AS api_count,
      COUNT(*) FILTER (WHERE client = 'sms')::int      AS sms_count
    FROM moment_channels
    GROUP BY artist_address
  )
  SELECT
    a.username,
    ltc.chat_id,
    pac.telegram_count,
    pac.web_count,
    pac.api_count,
    pac.sms_count
  FROM per_artist_counts pac
  INNER JOIN public.in_process_artists a ON a.address = pac.artist_address
  -- Lateral lookup: latest telegram chat_id for each artist actually being returned.
  CROSS JOIN LATERAL (
    SELECT msg.chat_id
    FROM public.in_process_message_metadata md
    INNER JOIN public.in_process_messages msg ON msg.metadata = md.id
    WHERE md.artist_address = pac.artist_address
      AND md.client = 'telegram'
      AND msg.chat_id IS NOT NULL
      AND msg.chat_id <> ''
    ORDER BY md.created_at DESC
    LIMIT 1
  ) ltc;
$function$;
