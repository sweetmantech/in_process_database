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
      AND a.telegram IS NOT NULL AND a.telegram <> ''
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
