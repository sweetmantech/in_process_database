CREATE TABLE "public"."in_process_token_admins" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "token_id" UUID,
  "artist_address" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_token_admins" enable ROW level security;

CREATE UNIQUE INDEX in_process_token_admins_pkey ON public.in_process_token_admins USING btree (id);

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_pkey" PRIMARY KEY USING index "in_process_token_admins_pkey";

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_artist_address_fkey" FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_token_admins" validate CONSTRAINT "in_process_token_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_token_id_fkey" FOREIGN key (token_id) REFERENCES in_process_tokens (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_token_admins" validate CONSTRAINT "in_process_token_admins_token_id_fkey";

ALTER TABLE "public"."in_process_token_admins"
ADD CONSTRAINT "in_process_token_admins_token_id_artist_address_unique" UNIQUE (token_id, artist_address);
