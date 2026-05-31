-- nudge_period being NULL now means nudge is disabled; non-NULL means enabled.
-- Drop nudge_enabled and make nudge_period nullable.

-- 1. Allow NULL in nudge_period.
ALTER TABLE public.account_notifications
  ALTER COLUMN nudge_period DROP NOT NULL,
  ALTER COLUMN nudge_period DROP DEFAULT;

-- 2. Disable nudge for rows that had nudge_enabled = false.
UPDATE public.account_notifications
  SET nudge_period = NULL
  WHERE nudge_enabled = false;

-- 3. Remove the now-redundant nudge_enabled column.
ALTER TABLE public.account_notifications
  DROP COLUMN nudge_enabled;

-- 4. Recreate get_nudges() using nudge_period IS NOT NULL instead of nudge_enabled = true.
DROP FUNCTION IF EXISTS public.get_nudges();

CREATE FUNCTION public.get_nudges()
RETURNS TABLE (
  artist_address       text,
  chat_id              text,
  days_since_last_moment integer,
  nudge_period         integer
)
LANGUAGE sql
STABLE
AS $function$
  WITH nudge_artists AS (
    SELECT an.artist_address, an.nudge_period
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.address = an.artist_address
    WHERE an.nudge_period IS NOT NULL
      AND a.telegram_username IS NOT NULL
      AND a.telegram_username <> ''
  ),
  inactive_artists AS (
    SELECT
      na.artist_address,
      na.nudge_period,
      (extract(epoch from now() - MAX(m.created_at)) / 86400)::integer AS days_inactive
    FROM nudge_artists na
    INNER JOIN public.in_process_collections c ON c.creator = na.artist_address
    INNER JOIN public.in_process_moments m     ON m.collection = c.id
    GROUP BY na.artist_address, na.nudge_period
    HAVING MAX(m.created_at) <= now() - make_interval(days => na.nudge_period)
  ),
  latest_chats AS (
    SELECT DISTINCT ON (md.artist_address)
      md.artist_address,
      msg.chat_id
    FROM public.in_process_message_metadata md
    INNER JOIN public.in_process_messages msg ON msg.metadata = md.id
    WHERE md.client = 'telegram'
      AND msg.chat_id IS NOT NULL
      AND msg.chat_id <> ''
    ORDER BY md.artist_address, md.created_at DESC
  )
  SELECT ia.artist_address, lc.chat_id, ia.days_inactive, ia.nudge_period
  FROM inactive_artists ia
  INNER JOIN latest_chats lc ON lc.artist_address = ia.artist_address
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.in_process_messages msg2
    INNER JOIN public.in_process_message_metadata md2 ON md2.id = msg2.metadata
    WHERE msg2.chat_id = lc.chat_id
      AND md2.artist_address = ia.artist_address
      AND msg2.role = 'assistant'
      AND md2.client = 'telegram'
      AND md2.created_at > now() - make_interval(days => GREATEST(ia.nudge_period, 2))
      AND (msg2.parts -> 0 ->> 'text') LIKE 'Hi! It''s been%since you last posted%'
  );
$function$;
