-- Create enum type for client
CREATE TYPE message_client AS ENUM ('telegram', 'sms');

create table "public"."in_process_message_metadata" (
  "id" uuid not null default gen_random_uuid(),
  "artist_address" text not null,
  "client" message_client not null,
  "created_at" timestamp with time zone not null default now()
);

alter table "public"."in_process_message_metadata" enable row level security;

CREATE UNIQUE INDEX in_process_message_metadata_pkey ON public.in_process_message_metadata USING btree (id);

alter table "public"."in_process_message_metadata" add constraint "in_process_message_metadata_pkey" PRIMARY KEY using index "in_process_message_metadata_pkey";

alter table "public"."in_process_message_metadata" add constraint "in_process_message_metadata_artist_address_fkey" FOREIGN KEY (artist_address) REFERENCES public.in_process_artists(address) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_message_metadata" validate constraint "in_process_message_metadata_artist_address_fkey";
