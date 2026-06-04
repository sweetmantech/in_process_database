CREATE TABLE "public"."in_process_artist_smart_wallets" (
  "smart_wallet_address" TEXT NOT NULL,
  "artist_address" TEXT NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_artist_smart_wallets" enable ROW level security;

CREATE UNIQUE INDEX in_process_artist_smart_wallets_pkey ON public.in_process_artist_smart_wallets USING btree (smart_wallet_address);

ALTER TABLE "public"."in_process_artist_smart_wallets"
ADD CONSTRAINT "in_process_artist_smart_wallets_pkey" PRIMARY KEY USING index "in_process_artist_smart_wallets_pkey";

ALTER TABLE "public"."in_process_artist_smart_wallets"
ADD CONSTRAINT "in_process_artist_smart_wallets_artist_address_fkey" FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_artist_smart_wallets" validate CONSTRAINT "in_process_artist_smart_wallets_artist_address_fkey";
