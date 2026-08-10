-- Fix get_nudges: stop requiring settings on the SQL primary wallet.
-- Read notification rows directly (telegram_chat_id is NOT NULL + unique);
-- compute inactivity across all of the artist's wallets.
DROP FUNCTION if EXISTS public.get_nudges ();

CREATE FUNCTION public.get_nudges () returns TABLE (
  wallet TEXT,
  chat_id TEXT,
  days_since_last_moment INTEGER,
  nudge_period INTEGER
) language sql stable AS $function$
  WITH artist_latest_moment AS (
    SELECT
      w.artist AS artist_id,
      MAX(m.created_at) AS latest_moment_at
    FROM public.in_process_wallets w
    INNER JOIN public.in_process_collections c ON c.creator = w.address
    INNER JOIN public.in_process_moments m ON m.collection = c.id
    GROUP BY w.artist
  )
  SELECT
    an.wallet,
    an.telegram_chat_id,
    (extract(epoch from now() - alm.latest_moment_at) / 86400)::integer AS days_since_last_moment,
    an.nudge_period
  FROM public.account_notifications an
  INNER JOIN public.in_process_wallets w ON w.address = an.wallet
  INNER JOIN public.in_process_artists a ON a.id = w.artist
  INNER JOIN artist_latest_moment alm ON alm.artist_id = w.artist
  WHERE an.nudge_period IS NOT NULL
    AND a.telegram IS NOT NULL
    AND a.telegram <> ''
    AND alm.latest_moment_at <= now() - make_interval(days => an.nudge_period)
    AND (
      an.last_nudge_sent_at IS NULL
      OR an.last_nudge_sent_at <= now() - make_interval(days => an.nudge_period)
    );
$function$;
