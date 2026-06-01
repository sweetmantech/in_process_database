-- Notification toggles now live in account_notifications; these legacy columns
-- on in_process_artists are redundant.
ALTER TABLE public.in_process_artists
  DROP COLUMN IF EXISTS notify_enabled,
  DROP COLUMN IF EXISTS nudge_enabled;
