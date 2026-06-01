-- Backfill: normalize existing smart_wallet values to lowercase. The unique index on
-- smart_wallet is case-sensitive, so the same address with different casing could exist
-- on multiple rows; keep one row per lower(smart_wallet) and clear the rest.
WITH ranked AS (
  SELECT
    address,
    row_number() OVER (PARTITION BY lower(smart_wallet) ORDER BY address) AS rn
  FROM public.in_process_artists
  WHERE smart_wallet IS NOT NULL
)
UPDATE public.in_process_artists t
SET smart_wallet = NULL
FROM ranked r
WHERE t.address = r.address
  AND r.rn > 1;

UPDATE public.in_process_artists
SET smart_wallet = lower(smart_wallet)
WHERE smart_wallet IS NOT NULL;

set check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.in_process_artists_smart_wallet_lowercase()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.smart_wallet IS NOT NULL THEN
    NEW.smart_wallet := lower(NEW.smart_wallet);
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER in_process_artists_smart_wallet_lowercase_trigger
BEFORE INSERT OR UPDATE OF smart_wallet ON public.in_process_artists
FOR EACH ROW
EXECUTE FUNCTION public.in_process_artists_smart_wallet_lowercase();
