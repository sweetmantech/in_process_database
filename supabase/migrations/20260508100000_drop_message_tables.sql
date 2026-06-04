-- Step 1: Rewrite moment_matches_channel
-- Channel is now stored directly on in_process_moments; no message table join needed.
-- Moments with channel IS NULL are treated as 'web' to preserve backward compatibility.
CREATE OR REPLACE FUNCTION public.moment_matches_channel (p_moment_id UUID, p_channel TEXT) returns BOOLEAN language sql stable AS $$
  SELECT
    p_channel IS NULL
    OR EXISTS (
      SELECT 1
      FROM public.in_process_moments m
      WHERE m.id = p_moment_id
        AND (
          m.channel = p_channel
          OR (p_channel = 'web' AND m.channel IS NULL)
        )
    )
$$;

-- Step 2: Rewrite get_nudges
-- chat_id now comes from account_notifications.telegram_chat_id.
-- Duplicate-send prevention uses last_nudge_sent_at instead of message text matching.
DROP FUNCTION if EXISTS public.get_nudges ();

CREATE FUNCTION public.get_nudges () returns TABLE (
  artist_address TEXT,
  chat_id TEXT,
  days_since_last_moment INTEGER,
  nudge_period INTEGER
) language sql stable AS $function$
  WITH nudge_artists AS (
    SELECT
      an.artist_address,
      an.nudge_period,
      an.telegram_chat_id,
      an.last_nudge_sent_at
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.address = an.artist_address
    WHERE an.nudge_period IS NOT NULL
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
      AND a.telegram_username IS NOT NULL
      AND a.telegram_username <> ''
  ),
  inactive_artists AS (
    SELECT
      na.artist_address,
      na.nudge_period,
      na.telegram_chat_id,
      na.last_nudge_sent_at,
      (extract(epoch from now() - MAX(m.created_at)) / 86400)::integer AS days_inactive
    FROM nudge_artists na
    INNER JOIN public.in_process_collections c ON c.creator = na.artist_address
    INNER JOIN public.in_process_moments m     ON m.collection = c.id
    GROUP BY na.artist_address, na.nudge_period, na.telegram_chat_id, na.last_nudge_sent_at
    HAVING MAX(m.created_at) <= now() - make_interval(days => na.nudge_period)
  )
  SELECT
    ia.artist_address,
    ia.telegram_chat_id,
    ia.days_inactive,
    ia.nudge_period
  FROM inactive_artists ia
  WHERE ia.last_nudge_sent_at IS NULL
     OR ia.last_nudge_sent_at <= now() - make_interval(days => ia.nudge_period);
$function$;

-- Step 3: Rewrite get_weekly_wrap_up_stats
-- Channel counts now come from in_process_moments.channel directly.
-- chat_id now comes from account_notifications.telegram_chat_id.
-- Moments with channel IS NULL are counted as web.
CREATE OR REPLACE FUNCTION public.get_weekly_wrap_up_stats (p_days INTEGER DEFAULT 7) returns TABLE (
  username TEXT,
  chat_id TEXT,
  telegram_count INTEGER,
  web_count INTEGER,
  api_count INTEGER,
  sms_count INTEGER
) language sql stable AS $function$
  WITH qualified_artists AS (
    SELECT a.address, an.telegram_chat_id
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.address = an.artist_address
    WHERE an.notify_enabled = true
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
      AND a.username IS NOT NULL AND a.username <> ''
      AND a.telegram_username IS NOT NULL AND a.telegram_username <> ''
  ),
  weekly_moments AS (
    SELECT m.id AS moment_id, c.creator AS artist_address, m.channel
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON m.collection = c.id
    INNER JOIN qualified_artists qa            ON qa.address = c.creator
    WHERE m.created_at >= NOW() - make_interval(days => p_days)
      AND c.protocol = 'in_process'
      AND c.chain_id = 8453
  ),
  per_artist_counts AS (
    SELECT
      artist_address,
      COUNT(*) FILTER (WHERE channel = 'telegram')::int               AS telegram_count,
      COUNT(*) FILTER (WHERE channel = 'web' OR channel IS NULL)::int AS web_count,
      COUNT(*) FILTER (WHERE channel = 'api')::int                    AS api_count,
      COUNT(*) FILTER (WHERE channel = 'sms')::int                    AS sms_count
    FROM weekly_moments
    GROUP BY artist_address
  )
  SELECT
    a.username,
    qa.telegram_chat_id,
    pac.telegram_count,
    pac.web_count,
    pac.api_count,
    pac.sms_count
  FROM per_artist_counts pac
  INNER JOIN public.in_process_artists a ON a.address = pac.artist_address
  INNER JOIN qualified_artists qa        ON qa.address = pac.artist_address;
$function$;

-- Step 4: Drop message tables (child tables first to respect foreign keys)
DROP TABLE IF EXISTS public.in_process_message_moment;

DROP TABLE IF EXISTS public.in_process_messages;

DROP TABLE IF EXISTS public.in_process_message_metadata;

-- Step 5: Drop enums that were only used by the dropped tables
DROP TYPE if EXISTS public.message_client;

DROP TYPE if EXISTS public.message_role;
