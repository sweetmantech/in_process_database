-- Delete orphan rows from in_process_artists: artists with no linked wallets
DELETE FROM public.in_process_artists a
WHERE NOT EXISTS (
  SELECT 1 FROM public.in_process_wallets w WHERE w.artist = a.id
);
