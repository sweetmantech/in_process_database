-- Update get_weekly_wrap_up_stats to use account_notifications for the notify_enabled gate.
-- The qualified_artists CTE now joins account_notifications so only artists who have
-- explicitly opted in (notify_enabled = true) receive a weekly wrap-up.

CREATE OR REPLACE FUNCTION public.get_weekly_wrap_up_stats(
  p_days integer DEFAULT 7
)
RETURNS TABLE (
  username       text,
  chat_id        text,
  telegram_count integer,
  web_count      integer,
  api_count      integer,
  sms_count      integer
)
LANGUAGE sql
STABLE
AS $function$
  -- Artists who opted in to notifications and have both username + telegram_username set.
  -- Start from account_notifications (smaller table) filtered by notify_enabled first,
  -- then join in_process_artists to apply the username/telegram_username conditions.
  WITH qualified_artists AS (
    SELECT a.address
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.address = an.artist_address
    WHERE an.notify_enabled = true
      AND a.username IS NOT NULL AND a.username <> ''
      AND a.telegram_username IS NOT NULL AND a.telegram_username <> ''
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
