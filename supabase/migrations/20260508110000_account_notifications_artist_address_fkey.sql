alter table "public"."account_notifications" add constraint "account_notifications_artist_address_fkey" FOREIGN KEY (artist_address) REFERENCES public.in_process_artists(address) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."account_notifications" validate constraint "account_notifications_artist_address_fkey";
