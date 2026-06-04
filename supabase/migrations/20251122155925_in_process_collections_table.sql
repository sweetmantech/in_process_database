CREATE TABLE "public"."in_process_collections" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "address" TEXT NOT NULL,
  "chain_id" NUMERIC NOT NULL,
  "uri" TEXT NOT NULL,
  "default_admin" TEXT NOT NULL,
  "payout_recipient" TEXT NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE "public"."in_process_collections" enable ROW level security;

CREATE UNIQUE INDEX in_process_collections_address_chain_id_unique ON public.in_process_collections USING btree (address, chain_id);

CREATE UNIQUE INDEX in_process_collections_pkey ON public.in_process_collections USING btree (id);

ALTER TABLE "public"."in_process_collections"
ADD CONSTRAINT "in_process_collections_pkey" PRIMARY KEY USING index "in_process_collections_pkey";

ALTER TABLE "public"."in_process_collections"
ADD CONSTRAINT "in_process_collections_address_chain_id_unique" UNIQUE USING index "in_process_collections_address_chain_id_unique";

ALTER TABLE "public"."in_process_collections"
ADD CONSTRAINT "in_process_collections_default_admin_fkey" FOREIGN key (default_admin) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_collections" validate CONSTRAINT "in_process_collections_default_admin_fkey";

SET
  check_function_bodies = off;

CREATE OR REPLACE FUNCTION public.in_process_collections_lowercase () returns trigger language plpgsql AS $function$
begin
  new.address := lower(new.address);
  new.default_admin := lower(new.default_admin);
  new.payout_recipient := lower(new.payout_recipient);
  return new;
end;
$function$;

CREATE TRIGGER in_process_collections_lowercase_trigger
BEFORE INSERT OR UPDATE ON public.in_process_collections FOR EACH ROW
EXECUTE FUNCTION public.in_process_collections_lowercase ();
