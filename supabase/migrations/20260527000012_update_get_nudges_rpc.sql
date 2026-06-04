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
      AND a.telegram IS NOT NULL
      AND a.telegram <> ''
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
