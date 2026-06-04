-- Create enum type for client
CREATE TYPE message_client AS ENUM('telegram', 'sms');

CREATE TABLE "public"."in_process_message_metadata" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "artist_address" TEXT NOT NULL,
  "client" message_client NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_message_metadata" enable ROW level security;

CREATE UNIQUE INDEX in_process_message_metadata_pkey ON public.in_process_message_metadata USING btree (id);

ALTER TABLE "public"."in_process_message_metadata"
ADD CONSTRAINT "in_process_message_metadata_pkey" PRIMARY KEY USING index "in_process_message_metadata_pkey";

ALTER TABLE "public"."in_process_message_metadata"
ADD CONSTRAINT "in_process_message_metadata_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_message_metadata" validate CONSTRAINT "in_process_message_metadata_artist_address_fkey";
