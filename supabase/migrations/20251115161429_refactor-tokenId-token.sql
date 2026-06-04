ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_token_id_artist_address_unique";

ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_token_id_fkey";

DROP INDEX if EXISTS "public"."in_process_token_admins_token_id_artist_address_unique";

ALTER TABLE "public"."in_process_token_admins"
DROP COLUMN "created_at";

ALTER TABLE "public"."in_process_token_admins"
DROP COLUMN "token_id";

ALTER TABLE "public"."in_process_token_admins"
ADD COLUMN "createdAt" TIMESTAMP WITH TIME ZONE;

ALTER TABLE "public"."in_process_token_admins"
ADD COLUMN "token" UUID DEFAULT GEN_RANDOM_UUID();

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_token_fkey" FOREIGN key (token) REFERENCES public.in_process_tokens (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_token_admins" validate CONSTRAINT "in_process_token_admins_token_fkey";

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_token_artist_address_unique" UNIQUE (token, artist_address);
