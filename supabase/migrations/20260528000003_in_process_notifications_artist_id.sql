-- Migrate in_process_notifications.artist (wallet address) → artist_id (UUID).
-- After this migration, notifications are keyed by artist account, not by wallet.
-- ---------------------------------------------------------------------------
-- 1. Add artist_id column (nullable first so we can populate it)
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_notifications
ADD COLUMN IF NOT EXISTS artist_id UUID;

-- ---------------------------------------------------------------------------
-- 2. Populate artist_id from in_process_wallets
-- ---------------------------------------------------------------------------
UPDATE public.in_process_notifications n
SET
  artist_id = w.artist
FROM
  public.in_process_wallets w
WHERE
  w.address = n.artist
  AND w.artist IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Remove rows with no matching artist (orphaned wallet addresses)
-- ---------------------------------------------------------------------------
DELETE FROM public.in_process_notifications
WHERE
  artist_id IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Set NOT NULL now that every row has an artist_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_notifications
ALTER COLUMN artist_id
SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 5. Drop old FK and artist column
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_notifications
DROP CONSTRAINT if EXISTS in_process_notifications_artist_fkey;

ALTER TABLE public.in_process_notifications
DROP COLUMN artist;

-- ---------------------------------------------------------------------------
-- 6. Add FK to in_process_artists
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_notifications
ADD CONSTRAINT in_process_notifications_artist_id_fkey FOREIGN key (artist_id) REFERENCES public.in_process_artists (id) ON UPDATE CASCADE ON DELETE CASCADE;
