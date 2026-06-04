-- Make artist_address nullable
ALTER TABLE "public"."in_process_message_metadata"
ALTER COLUMN "artist_address"
DROP NOT NULL;
