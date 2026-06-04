CREATE TABLE "public"."in_process_api_keys" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "name" TEXT NOT NULL,
  "artist_address" TEXT,
  "key_hash" TEXT,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
  "last_used" TIMESTAMP WITHOUT TIME ZONE
);

ALTER TABLE "public"."in_process_api_keys" enable ROW level security;

CREATE UNIQUE INDEX in_process_api_keys_pkey ON public.in_process_api_keys USING btree (id);

ALTER TABLE "public"."in_process_api_keys"
ADD CONSTRAINT "in_process_api_keys_pkey" PRIMARY KEY USING index "in_process_api_keys_pkey";

ALTER TABLE "public"."in_process_api_keys"
ADD CONSTRAINT "in_process_api_keys_artist_address_fkey" FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_api_keys" validate CONSTRAINT "in_process_api_keys_artist_address_fkey";
