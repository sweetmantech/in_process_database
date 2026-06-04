-- Redundant with in_process_artists_smart_wallet_key (smart_wallet UNIQUE); keep only the latter.
ALTER TABLE public.in_process_artists
DROP CONSTRAINT if EXISTS in_process_artists_address_smart_wallet_key;
