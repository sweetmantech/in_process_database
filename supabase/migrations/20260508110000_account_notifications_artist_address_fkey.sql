ALTER TABLE "public"."account_notifications"
ADD CONSTRAINT "account_notifications_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."account_notifications" validate CONSTRAINT "account_notifications_artist_address_fkey";
