-- One notification row per Telegram chat. telegram_chat_id is required.
-- Rows without a chat id cannot receive Telegram messages — drop them, then
-- enforce UNIQUE + NOT NULL so upsert can use onConflict: 'telegram_chat_id'.
UPDATE public.account_notifications
SET
  telegram_chat_id = NULL
WHERE
  telegram_chat_id = '';

-- Keep the most recently nudged row per chat_id; drop stale wallet copies.
DELETE FROM public.account_notifications an
WHERE
  an.telegram_chat_id IS NOT NULL
  AND an.wallet NOT IN (
    SELECT DISTINCT
      ON (telegram_chat_id) wallet
    FROM
      public.account_notifications
    WHERE
      telegram_chat_id IS NOT NULL
    ORDER BY
      telegram_chat_id,
      last_nudge_sent_at DESC NULLS LAST,
      (nudge_period IS NOT NULL) DESC,
      (notify_enabled IS TRUE) DESC,
      wallet
  );

-- Orphan wallet-only rows (no Telegram chat) cannot be notified.
DELETE FROM public.account_notifications
WHERE
  telegram_chat_id IS NULL;

ALTER TABLE public.account_notifications
DROP CONSTRAINT if EXISTS account_notifications_telegram_chat_id_key;

ALTER TABLE public.account_notifications
ADD CONSTRAINT account_notifications_telegram_chat_id_key UNIQUE (telegram_chat_id);

ALTER TABLE public.account_notifications
ALTER COLUMN telegram_chat_id
SET NOT NULL;
