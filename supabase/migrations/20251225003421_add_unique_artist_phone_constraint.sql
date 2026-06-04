-- Add unique constraint on artist_address and phone_number combination
CREATE UNIQUE INDEX in_process_artist_phones_artist_address_phone_number_unique ON public.in_process_artist_phones USING btree (artist_address, phone_number);

ALTER TABLE "public"."in_process_artist_phones"
ADD CONSTRAINT "in_process_artist_phones_artist_address_phone_number_unique" UNIQUE USING index "in_process_artist_phones_artist_address_phone_number_unique";
