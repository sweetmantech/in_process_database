DROP FUNCTION IF EXISTS public.set_zora_media_token_latest_holder_on_insert();

CREATE OR REPLACE FUNCTION public.set_zora_media_token_latest_holder_on_insert()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NOT EXISTS (
    SELECT 1
    FROM public.in_process_moments nm
    INNER JOIN public.in_process_collections nc
      ON nc.id = nm.collection
    WHERE nm.id = NEW.moment
      AND nc.protocol = 'zora_media'
  ) THEN
    RETURN NEW;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM public.in_process_transfers t
    WHERE t.moment = NEW.moment
      AND t.id <> NEW.id
      AND (
        t.transferred_at > NEW.transferred_at
        OR (t.transferred_at = NEW.transferred_at AND t.id > NEW.id)
      )
  ) THEN
    RETURN NEW;
  END IF;

  DELETE FROM public.in_process_transfers t
  WHERE t.id <> NEW.id
    AND t.moment = NEW.moment
    AND t.transferred_at <= NEW.transferred_at;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS zora_media_token_latest_holder_trigger ON public.in_process_transfers;

CREATE TRIGGER zora_media_token_latest_holder_trigger
AFTER INSERT ON public.in_process_transfers
FOR EACH ROW
EXECUTE FUNCTION public.set_zora_media_token_latest_holder_on_insert();
