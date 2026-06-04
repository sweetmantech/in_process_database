-- Final PR6 step: every artist_address / recipient / creator / collector /
-- default_admin column that still references in_process_artists(address) is
-- moved over to in_process_wallets(address). The artist entity (UUID PK) is
-- the source of truth for identity; the wallet table is the source of truth
-- for owned addresses.
-- ---------------------------------------------------------------------------
-- 1. Drop the orphaned legacy in_process_artist_smart_wallets table. Smart
--    wallet addresses now live on in_process_wallets.smart_wallet_address.
-- ---------------------------------------------------------------------------
DROP TABLE IF EXISTS public.in_process_artist_smart_wallets;

-- ---------------------------------------------------------------------------
-- 2. Defensive backfill: make sure every address that is currently the target
--    of a FK to in_process_artists(address) also has a row in
--    in_process_wallets. Migrations 3 / 6 already covered the common cases,
--    but any address inserted between then and now (or by a path that did
--    not touch the artists table) would otherwise fail validation.
-- ---------------------------------------------------------------------------
-- in_process_airdrops and in_process_collectors were dropped in migrations
-- 20260414090000 and 20260414130000 respectively, so they are intentionally
-- absent from this UNION.
INSERT INTO
  public.in_process_wallets (address)
SELECT DISTINCT
  addr
FROM
  (
    SELECT
      artist_address AS addr
    FROM
      public.account_notifications
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      artist_address
    FROM
      public.in_process_admins
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      artist_address
    FROM
      public.in_process_artist_phones
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      artist_address
    FROM
      public.in_process_arweave_uploads
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      creator
    FROM
      public.in_process_collections
    WHERE
      creator IS NOT NULL
    UNION
    SELECT
      artist_address
    FROM
      public.in_process_moment_comments
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      artist_address
    FROM
      public.in_process_moment_fee_recipients
    WHERE
      artist_address IS NOT NULL
    UNION
    SELECT
      artist
    FROM
      public.in_process_notifications
    WHERE
      artist IS NOT NULL
    UNION
    SELECT
      recipient
    FROM
      public.in_process_transfers
    WHERE
      recipient IS NOT NULL
  ) sources
ON CONFLICT (address) DO NOTHING;

-- ---------------------------------------------------------------------------
-- 3. Re-point FKs. Drop the existing constraint and add a new one pointing
--    at in_process_wallets(address). Behaviour (CASCADE / RESTRICT / SET NULL)
--    is preserved per table.
-- ---------------------------------------------------------------------------
ALTER TABLE public.account_notifications
DROP CONSTRAINT if EXISTS account_notifications_artist_address_fkey,
ADD CONSTRAINT account_notifications_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.in_process_admins
DROP CONSTRAINT if EXISTS in_process_admins_artist_address_fkey,
ADD CONSTRAINT in_process_admins_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.in_process_artist_phones
DROP CONSTRAINT if EXISTS in_process_artist_phones_artist_address_fkey,
ADD CONSTRAINT in_process_artist_phones_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.in_process_arweave_uploads
DROP CONSTRAINT if EXISTS in_process_arweave_uploads_artist_address_fkey,
ADD CONSTRAINT in_process_arweave_uploads_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

-- in_process_collections.default_admin was renamed to `creator` in
-- migration 20260305000001 (and the constraint name renamed alongside it),
-- so we re-point the current `creator_fkey` constraint.
ALTER TABLE public.in_process_collections
DROP CONSTRAINT if EXISTS in_process_collections_creator_fkey,
ADD CONSTRAINT in_process_collections_creator_fkey FOREIGN key (creator) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE public.in_process_moment_comments
DROP CONSTRAINT if EXISTS in_process_moment_comments_artist_address_fkey,
ADD CONSTRAINT in_process_moment_comments_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;

ALTER TABLE public.in_process_moment_fee_recipients
DROP CONSTRAINT if EXISTS in_process_moment_fee_recipients_artist_address_fkey,
ADD CONSTRAINT in_process_moment_fee_recipients_artist_address_fkey FOREIGN key (artist_address) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE RESTRICT;

ALTER TABLE public.in_process_notifications
DROP CONSTRAINT if EXISTS in_process_notifications_artist_fkey,
ADD CONSTRAINT in_process_notifications_artist_fkey FOREIGN key (artist) REFERENCES public.in_process_wallets (address) ON DELETE CASCADE;

ALTER TABLE public.in_process_transfers
DROP CONSTRAINT if EXISTS in_process_transfers_recipient_fkey,
ADD CONSTRAINT in_process_transfers_recipient_fkey FOREIGN key (recipient) REFERENCES public.in_process_wallets (address) ON DELETE SET NULL;

-- ---------------------------------------------------------------------------
-- 4. Finalize in_process_api_keys: the transitional artist_address column
--    is no longer used by any code (PR6 switched to artist_id). Drop it and
--    the now-obsolete FK in one shot.
-- ---------------------------------------------------------------------------
ALTER TABLE public.in_process_api_keys
DROP CONSTRAINT if EXISTS in_process_api_keys_artist_address_fkey;

ALTER TABLE public.in_process_api_keys
DROP COLUMN IF EXISTS artist_address;
