ALTER TABLE "public"."in_process_transfers"
ADD CONSTRAINT "in_process_transfers_recipient_fkey" FOREIGN key (recipient) REFERENCES "public"."in_process_artists" (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;
