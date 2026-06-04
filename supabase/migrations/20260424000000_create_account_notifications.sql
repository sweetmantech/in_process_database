CREATE TABLE public.account_notifications (
  artist_address TEXT NOT NULL PRIMARY KEY,
  notify_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  nudge_enabled BOOLEAN NOT NULL DEFAULT FALSE,
  nudge_period INTEGER NOT NULL DEFAULT 1
);

INSERT INTO
  public.account_notifications (artist_address, notify_enabled, nudge_enabled)
SELECT
  address,
  notify_enabled,
  nudge_enabled
FROM
  public.in_process_artists
WHERE
  notify_enabled = TRUE
  OR nudge_enabled = TRUE
ON CONFLICT (artist_address) DO NOTHING;
