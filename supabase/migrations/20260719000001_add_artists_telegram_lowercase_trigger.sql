CREATE OR REPLACE FUNCTION trg_artists_telegram_lowercase () returns trigger language plpgsql AS $$
BEGIN
  IF NEW.telegram IS NOT NULL THEN
    NEW.telegram := lower(NEW.telegram);
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER artists_telegram_lowercase
BEFORE INSERT OR UPDATE ON in_process_artists FOR EACH ROW
EXECUTE FUNCTION trg_artists_telegram_lowercase ();
