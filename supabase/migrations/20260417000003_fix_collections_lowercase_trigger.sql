-- Remove the reference to payout_recipient (dropped in 20260305000002)
-- from the in_process_collections_lowercase trigger function.
CREATE OR REPLACE FUNCTION public.in_process_collections_lowercase () returns trigger language plpgsql AS $function$
begin
  new.address := lower(new.address);
  new.creator := lower(new.creator);
  return new;
end;
$function$;
