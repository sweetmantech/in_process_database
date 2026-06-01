CREATE TABLE public.account_notifications (
  artist_address text NOT NULL PRIMARY KEY,
  notify_enabled boolean NOT NULL DEFAULT false,
  nudge_enabled boolean NOT NULL DEFAULT false,
  nudge_period integer NOT NULL DEFAULT 1
);

INSERT INTO public.account_notifications (artist_address, notify_enabled, nudge_enabled)
SELECT
  address,
  notify_enabled,
  nudge_enabled
FROM public.in_process_artists
WHERE notify_enabled = true OR nudge_enabled = true
ON CONFLICT (artist_address) DO NOTHING;
