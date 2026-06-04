-- Replace artist_id with wallet (primary wallet address) in both notification
-- tables. Primary wallet priority: external > privy > first available.
-- ===========================================================================
-- in_process_notifications
-- ===========================================================================
ALTER TABLE public.in_process_notifications
ADD COLUMN IF NOT EXISTS wallet TEXT;

UPDATE public.in_process_notifications n
SET
  wallet = (
    SELECT
      address
    FROM
      public.in_process_wallets w
    WHERE
      w.artist = n.artist_id
    ORDER BY
      CASE w.type
        WHEN 'external' THEN 1
        WHEN 'privy' THEN 2
        ELSE 3
      END
    LIMIT
      1
  );

DELETE FROM public.in_process_notifications
WHERE
  wallet IS NULL;

ALTER TABLE public.in_process_notifications
ALTER COLUMN wallet
SET NOT NULL;

ALTER TABLE public.in_process_notifications
DROP CONSTRAINT if EXISTS in_process_notifications_artist_id_fkey;

ALTER TABLE public.in_process_notifications
DROP COLUMN artist_id;

ALTER TABLE public.in_process_notifications
ADD CONSTRAINT in_process_notifications_wallet_fkey FOREIGN key (wallet) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

-- ===========================================================================
-- account_notifications
-- ===========================================================================
ALTER TABLE public.account_notifications
ADD COLUMN IF NOT EXISTS wallet TEXT;

UPDATE public.account_notifications an
SET
  wallet = (
    SELECT
      address
    FROM
      public.in_process_wallets w
    WHERE
      w.artist = an.artist_id
    ORDER BY
      CASE w.type
        WHEN 'external' THEN 1
        WHEN 'privy' THEN 2
        ELSE 3
      END
    LIMIT
      1
  );

DELETE FROM public.account_notifications
WHERE
  wallet IS NULL;

ALTER TABLE public.account_notifications
ALTER COLUMN wallet
SET NOT NULL;

ALTER TABLE public.account_notifications
DROP CONSTRAINT account_notifications_pkey;

ALTER TABLE public.account_notifications
ADD PRIMARY KEY (wallet);

ALTER TABLE public.account_notifications
DROP CONSTRAINT if EXISTS account_notifications_artist_id_fkey;

ALTER TABLE public.account_notifications
DROP COLUMN artist_id;

-- ===========================================================================
-- get_nudges: artist_id → wallet
-- ===========================================================================
DROP FUNCTION if EXISTS public.get_nudges ();

CREATE FUNCTION public.get_nudges () returns TABLE (
  wallet TEXT,
  chat_id TEXT,
  days_since_last_moment INTEGER,
  nudge_period INTEGER
) language sql stable AS $function$
  -- Step 1: find the primary wallet per artist across ALL wallets (not just
  -- those with notifications), using the same priority as getPrimaryWallet().
  WITH artist_primary_wallet AS (
    SELECT DISTINCT ON (artist)
      artist,
      address AS wallet
    FROM public.in_process_wallets
    ORDER BY artist,
      CASE type
        WHEN 'external' THEN 1
        WHEN 'privy'    THEN 2
        ELSE 3
      END,
      address
  ),
  -- Step 2: check nudge settings on the primary wallet only.
  -- If the primary wallet has nudge off, the artist is excluded entirely.
  primary_nudge AS (
    SELECT
      apw.artist    AS artist_id,
      apw.wallet,
      an.nudge_period,
      an.telegram_chat_id,
      an.last_nudge_sent_at
    FROM artist_primary_wallet apw
    INNER JOIN public.account_notifications an ON an.wallet = apw.wallet
    INNER JOIN public.in_process_artists a      ON a.id = apw.artist
    WHERE an.nudge_period IS NOT NULL
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
      AND a.telegram IS NOT NULL AND a.telegram <> ''
  ),
  -- Step 3: find the latest moment across ALL wallets of each artist.
  artist_latest_moment AS (
    SELECT
      w.artist          AS artist_id,
      MAX(m.created_at) AS latest_moment_at
    FROM public.in_process_wallets w
    INNER JOIN public.in_process_collections c ON c.creator = w.address
    INNER JOIN public.in_process_moments m      ON m.collection = c.id
    GROUP BY w.artist
  )
  SELECT
    pn.wallet,
    pn.telegram_chat_id,
    (extract(epoch from now() - alm.latest_moment_at) / 86400)::integer AS days_inactive,
    pn.nudge_period
  FROM primary_nudge pn
  INNER JOIN artist_latest_moment alm ON alm.artist_id = pn.artist_id
  WHERE alm.latest_moment_at <= now() - make_interval(days => pn.nudge_period)
    AND (pn.last_nudge_sent_at IS NULL
      OR pn.last_nudge_sent_at <= now() - make_interval(days => pn.nudge_period));
$function$;

-- ===========================================================================
-- get_weekly_wrap_up_stats: artist_id → wallet
-- ===========================================================================
CREATE OR REPLACE FUNCTION public.get_weekly_wrap_up_stats (p_days INTEGER DEFAULT 7) returns TABLE (
  username TEXT,
  chat_id TEXT,
  telegram_count INTEGER,
  web_count INTEGER,
  api_count INTEGER,
  sms_count INTEGER
) language sql stable AS $function$
  WITH qualified_notifications AS (
    SELECT
      an.wallet,
      an.telegram_chat_id
    FROM public.account_notifications an
    WHERE an.notify_enabled = true
      AND an.telegram_chat_id IS NOT NULL
      AND an.telegram_chat_id <> ''
  ),
  qualified_artists AS (
    SELECT
      qn.wallet,
      a.username,
      qn.telegram_chat_id
    FROM qualified_notifications qn
    INNER JOIN public.in_process_wallets w ON w.address = qn.wallet
    INNER JOIN public.in_process_artists a ON a.id = w.artist
    WHERE a.username IS NOT NULL AND a.username <> ''
      AND a.telegram IS NOT NULL AND a.telegram <> ''
  ),
  weekly_moments AS (
    SELECT m.id AS moment_id, qa.wallet, m.channel
    FROM public.in_process_moments m
    INNER JOIN public.in_process_collections c ON m.collection = c.id
    INNER JOIN qualified_artists qa ON qa.wallet = c.creator
    WHERE m.created_at >= NOW() - make_interval(days => p_days)
      AND c.protocol = 'in_process'
      AND c.chain_id = 8453
  ),
  per_wallet_counts AS (
    SELECT
      wallet,
      COUNT(*) FILTER (WHERE channel = 'telegram')::int               AS telegram_count,
      COUNT(*) FILTER (WHERE channel = 'web' OR channel IS NULL)::int AS web_count,
      COUNT(*) FILTER (WHERE channel = 'api')::int                    AS api_count,
      COUNT(*) FILTER (WHERE channel = 'sms')::int                    AS sms_count
    FROM weekly_moments
    GROUP BY wallet
  )
  SELECT
    qa.username,
    qa.telegram_chat_id,
    pwc.telegram_count,
    pwc.web_count,
    pwc.api_count,
    pwc.sms_count
  FROM per_wallet_counts pwc
  INNER JOIN qualified_artists qa ON qa.wallet = pwc.wallet;
$function$;
