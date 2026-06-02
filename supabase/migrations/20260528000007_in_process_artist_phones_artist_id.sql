-- Migrate in_process_artist_phones.artist_address (wallet) → artist_id (UUID).
-- Phone numbers are per artist account, not per wallet.

-- ---------------------------------------------------------------------------
-- 1. Add artist_id column (nullable first so we can populate it)
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_artist_phones
  ADD COLUMN IF NOT EXISTS artist_id uuid;

-- ---------------------------------------------------------------------------
-- 2. Populate artist_id from in_process_wallets
-- ---------------------------------------------------------------------------
UPDATE public.in_process_artist_phones p
SET artist_id = w.artist
FROM public.in_process_wallets w
WHERE w.address = p.artist_address AND w.artist IS NOT NULL;

-- ---------------------------------------------------------------------------
-- 3. Remove rows with no matching artist (orphaned wallet addresses)
-- ---------------------------------------------------------------------------
DELETE FROM public.in_process_artist_phones WHERE artist_id IS NULL;

-- ---------------------------------------------------------------------------
-- 4. Deduplicate: one phone row per artist (prefer verified, then newest)
-- ---------------------------------------------------------------------------
DELETE FROM public.in_process_artist_phones p
WHERE p.id NOT IN (
  SELECT DISTINCT ON (artist_id) id
  FROM public.in_process_artist_phones
  ORDER BY artist_id, verified DESC, created_at DESC
);

-- ---------------------------------------------------------------------------
-- 5. Set NOT NULL now that every row has an artist_id
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_artist_phones
  ALTER COLUMN artist_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 6. Drop old FK and artist_address column
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_artist_phones
  DROP CONSTRAINT IF EXISTS in_process_artist_phones_artist_address_fkey;

ALTER TABLE public.in_process_artist_phones
  DROP COLUMN artist_address;

-- ---------------------------------------------------------------------------
-- 7. One phone number per artist
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX in_process_artist_phones_artist_id_unique
  ON public.in_process_artist_phones (artist_id);

ALTER TABLE public.in_process_artist_phones
  ADD CONSTRAINT in_process_artist_phones_artist_id_unique
    UNIQUE USING INDEX in_process_artist_phones_artist_id_unique;

-- ---------------------------------------------------------------------------
-- 8. FK to in_process_artists
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_artist_phones
  ADD CONSTRAINT in_process_artist_phones_artist_id_fkey
    FOREIGN KEY (artist_id) REFERENCES public.in_process_artists(id)
    ON UPDATE CASCADE ON DELETE CASCADE;
