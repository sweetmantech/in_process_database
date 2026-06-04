ALTER TABLE "public"."in_process_artists"
ADD COLUMN "smart_wallet" TEXT;

CREATE INDEX in_process_artists_smart_wallet_idx ON public.in_process_artists USING btree (smart_wallet);

CREATE UNIQUE INDEX in_process_artists_smart_wallet_key ON public.in_process_artists USING btree (smart_wallet);

ALTER TABLE "public"."in_process_artists"
ADD CONSTRAINT "in_process_artists_smart_wallet_key" UNIQUE USING index "in_process_artists_smart_wallet_key";
