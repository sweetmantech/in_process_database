CREATE UNIQUE INDEX in_process_artists_address_smart_wallet_key
  ON public.in_process_artists USING btree (address, smart_wallet);

ALTER TABLE public.in_process_artists
  ADD CONSTRAINT in_process_artists_address_smart_wallet_key
  UNIQUE USING INDEX in_process_artists_address_smart_wallet_key;
