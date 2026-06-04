CREATE TYPE wallet_type AS ENUM('privy', 'farcaster', 'external');

CREATE TABLE in_process_artists_v2 (
  id UUID PRIMARY KEY DEFAULT GEN_RANDOM_UUID(),
  address TEXT UNIQUE NOT NULL,
  username TEXT UNIQUE,
  bio TEXT,
  x TEXT,
  telegram TEXT,
  instagram TEXT
);

CREATE TABLE in_process_wallets (
  address TEXT PRIMARY KEY,
  artist UUID REFERENCES in_process_artists_v2 (id),
  type wallet_type,
  smart_wallet_address TEXT
);

CREATE OR REPLACE FUNCTION trg_wallets_lowercase () returns trigger language plpgsql AS $$
BEGIN
  NEW.address := lower(NEW.address);
  IF NEW.smart_wallet_address IS NOT NULL THEN
    NEW.smart_wallet_address := lower(NEW.smart_wallet_address);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER wallets_lowercase
BEFORE INSERT OR UPDATE ON in_process_wallets FOR EACH ROW
EXECUTE FUNCTION trg_wallets_lowercase ();
