-- Optimize get_nudges: select nudge-enabled notification rows first,
-- then compute latest moments only for those artists (not the whole table).
DROP FUNCTION if EXISTS public.get_nudges ();

CREATE FUNCTION public.get_nudges () returns TABLE (
  wallet TEXT,
  chat_id TEXT,
  days_since_last_moment INTEGER,
  nudge_period INTEGER
) language sql stable AS $function$
  WITH nudge_candidates AS (
    SELECT
      an.wallet,
      an.telegram_chat_id,
      an.nudge_period,
      an.last_nudge_sent_at,
      w.artist AS artist_id
    FROM public.account_notifications an
    INNER JOIN public.in_process_wallets w ON w.address = an.wallet
    INNER JOIN public.in_process_artists a ON a.id = w.artist
    WHERE an.nudge_period IS NOT NULL
      AND a.telegram IS NOT NULL
      AND a.telegram <> ''
      AND (
        an.last_nudge_sent_at IS NULL
        OR an.last_nudge_sent_at <= now() - make_interval(days => an.nudge_period)
      )
  ),
  artist_latest_moment AS (
    SELECT
      nc.artist_id,
      MAX(m.created_at) AS latest_moment_at
    FROM nudge_candidates nc
    INNER JOIN public.in_process_wallets w ON w.artist = nc.artist_id
    INNER JOIN public.in_process_collections c ON c.creator = w.address
    INNER JOIN public.in_process_moments m ON m.collection = c.id
    GROUP BY nc.artist_id
  )
  SELECT
    nc.wallet,
    nc.telegram_chat_id,
    (extract(epoch from now() - alm.latest_moment_at) / 86400)::integer AS days_since_last_moment,
    nc.nudge_period
  FROM nudge_candidates nc
  INNER JOIN artist_latest_moment alm ON alm.artist_id = nc.artist_id
  WHERE alm.latest_moment_at <= now() - make_interval(days => nc.nudge_period);
$function$;
