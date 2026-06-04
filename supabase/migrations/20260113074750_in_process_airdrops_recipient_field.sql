ALTER TABLE "public"."in_process_airdrops"
DROP CONSTRAINT "in_process_airdrops_artist_address_fkey";

DROP INDEX if EXISTS "public"."in_process_airdrops_moment_artist_address_idx";

ALTER TABLE "public"."in_process_airdrops"
DROP COLUMN "artist_address";

ALTER TABLE "public"."in_process_airdrops"
ADD COLUMN "recipient" TEXT NOT NULL;

ALTER TABLE "public"."in_process_airdrops"
ADD CONSTRAINT "in_process_airdrops_recipient_fkey" FOREIGN key (recipient) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_airdrops" validate CONSTRAINT "in_process_airdrops_recipient_fkey";

ALTER TABLE "public"."in_process_airdrops"
ADD CONSTRAINT "in_process_airdrops_moment_recipient_unique" UNIQUE (moment, recipient);
