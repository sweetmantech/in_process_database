CREATE OR REPLACE FUNCTION public.get_daily_nudges (
  p_inactivity_days INTEGER DEFAULT 3,
  p_recent_assistant_days INTEGER DEFAULT 7
) returns TABLE (
  artist_address TEXT,
  room_id TEXT,
  days_since_last_moment INTEGER
) language sql stable AS $function$
  WITH inactive_artists AS (
    SELECT
      a.address,
      (extract(epoch from now() - MAX(m.created_at)) / 86400)::integer AS days_inactive
    FROM public.in_process_artists a
    JOIN public.in_process_collections c ON c.creator = a.address
    JOIN public.in_process_moments m ON m.collection = c.id
    WHERE a.nudge_enabled = true
      AND a.telegram_username IS NOT NULL
      AND a.telegram_username <> ''
    GROUP BY a.address
    HAVING MAX(m.created_at) <= now() - make_interval(days => p_inactivity_days)
  ),
  latest_rooms AS (
    SELECT DISTINCT ON (md.artist_address)
      md.artist_address,
      msg.room
    FROM public.in_process_message_metadata md
    JOIN public.in_process_messages msg ON msg.metadata = md.id
    WHERE md.client = 'telegram'
      AND msg.room IS NOT NULL
    ORDER BY md.artist_address, md.created_at DESC
  )
  SELECT ia.address, lr.room, ia.days_inactive
  FROM inactive_artists ia
  JOIN latest_rooms lr ON lr.artist_address = ia.address
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.in_process_messages msg2
    JOIN public.in_process_message_metadata md2 ON md2.id = msg2.metadata
    WHERE msg2.room = lr.room
      AND msg2.role = 'assistant'
      AND md2.client = 'telegram'
      AND md2.created_at > now() - make_interval(days => p_recent_assistant_days)
  );
$function$;
