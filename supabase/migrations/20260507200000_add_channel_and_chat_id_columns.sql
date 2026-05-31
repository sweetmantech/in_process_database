-- Add channel to in_process_moments
ALTER TABLE public.in_process_moments
  ADD COLUMN channel text CHECK (channel IN ('sms', 'telegram', 'web', 'api'));

-- Add telegram_chat_id and last_nudge_sent_at to account_notifications
ALTER TABLE public.account_notifications
  ADD COLUMN telegram_chat_id text,
  ADD COLUMN last_nudge_sent_at timestamptz;

-- Migrate channel: resolve each moment's channel via the message_moment -> messages -> metadata chain.
UPDATE public.in_process_moments m
SET channel = mmd.client::text
FROM public.in_process_message_moment mm
INNER JOIN public.in_process_messages msg ON msg.id = mm.message
INNER JOIN public.in_process_message_metadata mmd ON mmd.id = msg.metadata
WHERE mm.moment = m.id;

-- Migrate telegram_chat_id: copy the latest Telegram chat_id per artist from messages to account_notifications.
-- Artists without an existing row are inserted; existing rows are updated.
INSERT INTO public.account_notifications (artist_address, telegram_chat_id)
SELECT lc.artist_address, lc.chat_id
FROM (
  SELECT DISTINCT ON (md.artist_address)
    md.artist_address,
    msg.chat_id
  FROM public.in_process_message_metadata md
  INNER JOIN public.in_process_messages msg ON msg.metadata = md.id
  WHERE md.client = 'telegram'
    AND md.artist_address IS NOT NULL
    AND msg.chat_id IS NOT NULL
    AND msg.chat_id <> ''
  ORDER BY md.artist_address, md.created_at DESC
) lc
ON CONFLICT (artist_address) DO UPDATE
  SET telegram_chat_id = EXCLUDED.telegram_chat_id;
