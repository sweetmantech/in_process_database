-- Drop the previous unique constraint on artist_address and phone_number combination
ALTER TABLE "public"."in_process_artist_phones"
DROP CONSTRAINT if EXISTS "in_process_artist_phones_artist_address_phone_number_unique";

DROP INDEX if EXISTS "public"."in_process_artist_phones_artist_address_phone_number_unique";

-- Add unique constraint on phone_number
CREATE UNIQUE INDEX in_process_artist_phones_phone_number_unique ON public.in_process_artist_phones USING btree (phone_number);

ALTER TABLE "public"."in_process_artist_phones"
ADD CONSTRAINT "in_process_artist_phones_phone_number_unique" UNIQUE USING index "in_process_artist_phones_phone_number_unique";
