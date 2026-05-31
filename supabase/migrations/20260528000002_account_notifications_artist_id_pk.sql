-- Migrate account_notifications from wallet-address PK to artist UUID PK.
-- After this migration, notification settings are per-artist-account, not per-wallet.

-- ---------------------------------------------------------------------------
-- 1. Add artist_id column (nullable first so we can populate it)
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
  ADD COLUMN IF NOT EXISTS artist_id uuid;

-- ---------------------------------------------------------------------------
-- 2. Populate artist_id from in_process_wallets
-- ---------------------------------------------------------------------------
UPDATE public.account_notifications an
SET artist_id = w.artist
FROM public.in_process_wallets w
WHERE w.address = an.artist_address AND w.artist IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Remove rows with no matching artist (orphaned wallet addresses)
-- ---------------------------------------------------------------------------
DELETE FROM public.account_notifications WHERE artist_id IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Deduplicate: for artists that appear under multiple wallet addresses,
--    keep the row with the richest settings (prefer notify_enabled, then
--    nudge_period set, then telegram_chat_id set).
-- ---------------------------------------------------------------------------
DELETE FROM public.account_notifications an
WHERE an.artist_address NOT IN (
  SELECT DISTINCT ON (artist_id) artist_address
  FROM public.account_notifications
  ORDER BY
    artist_id,
    notify_enabled DESC,
    (nudge_period IS NOT NULL) DESC,
    (telegram_chat_id IS NOT NULL) DESC
);

-- ---------------------------------------------------------------------------
-- 5. Set NOT NULL on artist_id now that every row has one
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
  ALTER COLUMN artist_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. Swap primary key: drop address PK, add artist_id PK
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
  DROP CONSTRAINT account_notifications_pkey;

ALTER TABLE public.account_notifications
  ADD PRIMARY KEY (artist_id);

-- ---------------------------------------------------------------------------
-- 7. Add FK to in_process_artists
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
  ADD CONSTRAINT account_notifications_artist_id_fkey
    FOREIGN KEY (artist_id) REFERENCES public.in_process_artists(id)
    ON UPDATE CASCADE ON DELETE CASCADE;

-- ---------------------------------------------------------------------------
-- 8. Drop the old artist_address FK and column
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
  DROP CONSTRAINT IF EXISTS account_notifications_artist_address_fkey;

ALTER TABLE public.account_notifications
  DROP COLUMN artist_address;

-- ---------------------------------------------------------------------------
-- 9. Update get_nudges RPC: remove in_process_artists.address reference,
--    join through artist_id; return artist_id (uuid) instead of artist_address.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_nudges();

CREATE FUNCTION public.get_nudges()
RETURNS TABLE (
  artist_id              uuid,
  chat_id                text,
  days_since_last_moment integer,
  nudge_period           integer
)
LANGUAGE sql
STABLE
AS $function$
  WITH nudge_artists AS (
    SELECT
      an.artist_id,
      an.nudge_period,
      an.telegram_chat_id,
      an.last_nudge_sent_at
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.id = an.artist_id
    WHERE an.nudge_period IS NOT NULL
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
      AND a.telegram IS NOT NULL
      AND a.telegram <> ''
  ),
  artist_wallets AS (
    SELECT
      na.artist_id,
      na.nudge_period,
      na.telegram_chat_id,
      na.last_nudge_sent_at,
      w.address AS wallet_address
    FROM nudge_artists na
    INNER JOIN public.in_process_wallets w ON w.artist = na.artist_id
  ),
  inactive_artists AS (
    SELECT
      aw.artist_id,
      aw.nudge_period,
      aw.telegram_chat_id,
      aw.last_nudge_sent_at,
      (extract(epoch from now() - MAX(m.created_at)) / 86400)::integer AS days_inactive
    FROM artist_wallets aw
    INNER JOIN public.in_process_collections c ON c.creator = aw.wallet_address
    INNER JOIN public.in_process_moments m      ON m.collection = c.id
    GROUP BY aw.artist_id, aw.nudge_period, aw.telegram_chat_id, aw.last_nudge_sent_at
    HAVING MAX(m.created_at) <= now() - make_interval(days => aw.nudge_period)
  )
  SELECT
    ia.artist_id,
    ia.telegram_chat_id,
    ia.days_inactive,
    ia.nudge_period
  FROM inactive_artists ia
  WHERE ia.last_nudge_sent_at IS NULL
     OR ia.last_nudge_sent_at <= now() - make_interval(days => ia.nudge_period);
$function$;

-- ---------------------------------------------------------------------------
-- 10. Update get_weekly_wrap_up_stats RPC: remove in_process_artists.address
--     reference; join through artist_id and then in_process_wallets.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_weekly_wrap_up_stats(
  p_days integer DEFAULT 7
)
RETURNS TABLE (
  username       text,
  chat_id        text,
  telegram_count integer,
  web_count      integer,
  api_count      integer,
  sms_count      integer
)
LANGUAGE sql
STABLE
AS $function$
  WITH qualified_artists AS (
    SELECT
      an.artist_id,
      a.username,
      an.telegram_chat_id
    FROM public.account_notifications an
    INNER JOIN public.in_process_artists a ON a.id = an.artist_id
    WHERE an.notify_enabled = true
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
      AND a.username IS NOT NULL AND a.username <> ''
      AND a.telegram IS NOT NULL AND a.telegram <> ''
  ),
  artist_wallets AS (
    SELECT
      qa.artist_id,
      qa.username,
      qa.telegram_chat_id,
      w.address AS wallet_address
    FROM qualified_artists qa
    INNER JOIN public.in_process_wallets w ON w.artist = qa.artist_id
  ),
  weekly_moments AS (
    SELECT m.id AS moment_id, aw.artist_id, m.channel
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON m.collection = c.id
    INNER JOIN artist_wallets aw               ON aw.wallet_address = c.creator
    WHERE m.created_at >= NOW() - make_interval(days => p_days)
      AND c.protocol = 'in_process'
      AND c.chain_id = 8453
  ),
  per_artist_counts AS (
    SELECT
      artist_id,
      COUNT(*) FILTER (WHERE channel = 'telegram')::int               AS telegram_count,
      COUNT(*) FILTER (WHERE channel = 'web' OR channel IS NULL)::int AS web_count,
      COUNT(*) FILTER (WHERE channel = 'api')::int                    AS api_count,
      COUNT(*) FILTER (WHERE channel = 'sms')::int                    AS sms_count
    FROM weekly_moments
    GROUP BY artist_id
  )
  SELECT
    qa.username,
    qa.telegram_chat_id,
    pac.telegram_count,
    pac.web_count,
    pac.api_count,
    pac.sms_count
  FROM per_artist_counts pac
  INNER JOIN qualified_artists qa ON qa.artist_id = pac.artist_id;
$function$;
