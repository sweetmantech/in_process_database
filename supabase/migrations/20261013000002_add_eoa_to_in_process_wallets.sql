ALTER TABLE in_process_wallets
ADD COLUMN eoa TEXT REFERENCES in_process_wallets (address) ON UPDATE CASCADE ON DELETE SET NULL;

CREATE OR REPLACE FUNCTION trg_wallets_lowercase () returns trigger language plpgsql AS $$
BEGIN
  NEW.address := lower(NEW.address);
  IF NEW.eoa IS NOT NULL THEN
    NEW.eoa := lower(NEW.eoa);
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION trg_wallets_sync_operator_artist () returns trigger language plpgsql AS $$
BEGIN
  UPDATE in_process_wallets
  SET artist = NEW.artist
  WHERE eoa = NEW.address
    AND artist IS DISTINCT FROM NEW.artist;
  RETURN NEW;
END;
$$;

CREATE TRIGGER wallets_sync_operator_artist
AFTER UPDATE OF artist ON in_process_wallets FOR EACH ROW WHEN (old.artist IS DISTINCT FROM new.artist)
EXECUTE FUNCTION trg_wallets_sync_operator_artist ();
