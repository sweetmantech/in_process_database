-- Replace wallet (TEXT → in_process_wallets) with artist (UUID → in_process_artists)
-- in in_process_hidden. An artist may hide using any of their wallets; storing the
-- artist UUID directly removes the need for multi-wallet resolution at query time.
-- 1. Add artist column (nullable until populated)
ALTER TABLE public.in_process_hidden
ADD COLUMN "artist" UUID;

-- 2. Populate artist from the wallet → in_process_wallets.artist mapping
UPDATE public.in_process_hidden h
SET
  artist = w.artist
FROM
  public.in_process_wallets w
WHERE
  w.address = h.wallet;

-- 3. Enforce NOT NULL now that every row is populated
ALTER TABLE public.in_process_hidden
ALTER COLUMN artist
SET NOT NULL;

-- 4. Add FK to in_process_artists
ALTER TABLE public.in_process_hidden
ADD CONSTRAINT "in_process_hidden_artist_fkey" FOREIGN key (artist) REFERENCES public.in_process_artists (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE public.in_process_hidden validate CONSTRAINT "in_process_hidden_artist_fkey";

-- 5. Swap unique constraint: (moment, wallet) → (moment, artist)
ALTER TABLE public.in_process_hidden
DROP CONSTRAINT "in_process_hidden_moment_wallet_unique";

DROP INDEX if EXISTS public.in_process_hidden_moment_wallet_unique;

CREATE UNIQUE INDEX in_process_hidden_moment_artist_unique ON public.in_process_hidden (moment, artist);

ALTER TABLE public.in_process_hidden
ADD CONSTRAINT "in_process_hidden_moment_artist_unique" UNIQUE USING index in_process_hidden_moment_artist_unique;

-- 6. Drop wallet FK and column
ALTER TABLE public.in_process_hidden
DROP CONSTRAINT "in_process_hidden_wallet_fkey";

ALTER TABLE public.in_process_hidden
DROP COLUMN wallet;
