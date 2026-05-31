-- Make artist_address nullable
alter table "public"."in_process_message_metadata"
  alter column "artist_address" drop not null;
