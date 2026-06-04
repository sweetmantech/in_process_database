-- Drop the old fixed-period nudge function.
DROP FUNCTION if EXISTS public.get_daily_nudges (INTEGER, INTEGER);

-- get_nudges: returns artists due for a nudge, respecting each artist's own nudge_period.
--
-- An artist is included when ALL of the following hold:
--   1. account_notifications.nudge_enabled = true
--   2. Their most recent moment is older than nudge_period days  (inactivity gate)
--   3. No nudge message has been sent to their chat in the last nudge_period days
--      (cooldown gate — nudge messages are identified by parts[0].text starting with
--       'Hi! It''s been', so other assistant messages do not reset the cooldown)
CREATE FUNCTION public.get_nudges () returns TABLE (
  artist_address TEXT,
  chat_id TEXT,
  days_since_last_moment INTEGER,
  nudge_period INTEGER
) language sql stable AS $function$
  -- Artists opted in to nudges, paired with their period (days).
  WITH nudge_artists AS (
    SELECT an.artist_address, an.nudge_period
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.address = an.artist_address
    WHERE an.nudge_enabled = true
      AND a.telegram_username IS NOT NULL
      AND a.telegram_username <> ''
  ),
  -- Keep only artists whose last moment is older than their own nudge_period.
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
  -- Latest telegram chat_id per artist (used for both the result and the cooldown check).
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
  -- Cooldown: skip artists who already received a nudge within the last nudge_period days.
  -- Match only nudge messages (parts[0].text starts with 'Hi! It''s been') so that
  -- other assistant replies (/start, /remind confirmations, etc.) do not reset the cooldown.
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
