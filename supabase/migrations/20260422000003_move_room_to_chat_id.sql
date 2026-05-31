-- Add chat_id as a plain text column (no FK) to replace the room FK
alter table "public"."in_process_messages"
  add column "chat_id" text null default null;

-- Copy existing room values into chat_id
UPDATE "public"."in_process_messages"
  SET "chat_id" = "room"
  WHERE "room" IS NOT NULL;

-- Drop FK constraint and room column
alter table "public"."in_process_messages"
  drop constraint "in_process_messages_room_fkey";

DROP INDEX IF EXISTS idx_in_process_messages_room;

alter table "public"."in_process_messages"
  drop column "room";

CREATE INDEX idx_in_process_messages_chat_id
  ON public.in_process_messages USING btree (chat_id);

-- Recreate get_daily_nudges RPC with chat_id instead of room_id.
-- DROP first because PostgreSQL disallows changing a function's return type via CREATE OR REPLACE.
DROP FUNCTION IF EXISTS public.get_daily_nudges(integer, integer);

CREATE FUNCTION public.get_daily_nudges(
  p_inactivity_days integer DEFAULT 3,
  p_recent_assistant_days integer DEFAULT 7
)
RETURNS TABLE (
  artist_address text,
  chat_id text,
  days_since_last_moment integer
)
LANGUAGE sql
STABLE
AS $function$
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
  latest_chats AS (
    SELECT DISTINCT ON (md.artist_address)
      md.artist_address,
      msg.chat_id
    FROM public.in_process_message_metadata md
    JOIN public.in_process_messages msg ON msg.metadata = md.id
    WHERE md.client = 'telegram'
      AND msg.chat_id IS NOT NULL
    ORDER BY md.artist_address, md.created_at DESC
  )
  SELECT ia.address, lc.chat_id, ia.days_inactive
  FROM inactive_artists ia
  JOIN latest_chats lc ON lc.artist_address = ia.address
  WHERE NOT EXISTS (
    SELECT 1
    FROM public.in_process_messages msg2
    JOIN public.in_process_message_metadata md2 ON md2.id = msg2.metadata
    WHERE msg2.chat_id = lc.chat_id
      AND md2.artist_address = ia.address
      AND msg2.role = 'assistant'
      AND md2.client = 'telegram'
      AND md2.created_at > now() - make_interval(days => p_recent_assistant_days)
  );
$function$;

-- Remove the rooms registry table — no longer needed now that chat_id is a plain column
DROP TABLE IF EXISTS "public"."in_process_rooms";
