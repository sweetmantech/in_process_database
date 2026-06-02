-- Lowercase in_process_artists.address on insert / update of address.

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.in_process_artists_address_lowercase()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.address IS NOT NULL THEN
    NEW.address := lower(NEW.address);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER in_process_artists_address_lowercase_trigger
BEFORE INSERT OR UPDATE OF address ON public.in_process_artists
FOR EACH ROW
EXECUTE FUNCTION public.in_process_artists_address_lowercase();
