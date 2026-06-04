ALTER TABLE "public"."in_process_moments"
DROP CONSTRAINT "in_process_moments_collection_id_fkey";

ALTER TABLE "public"."in_process_moments"
DROP CONSTRAINT "in_process_moments_collection_id_token_id_unique";

DROP INDEX if EXISTS "public"."in_process_moments_collection_id_token_id_unique";

ALTER TABLE "public"."in_process_moments"
DROP COLUMN "collection_id";

ALTER TABLE "public"."in_process_moments"
ADD COLUMN "collection" UUID NOT NULL;

ALTER TABLE "public"."in_process_moments"
ADD CONSTRAINT "in_process_moments_collection_fkey" FOREIGN key (collection) REFERENCES public.in_process_collections (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moments" validate CONSTRAINT "in_process_moments_collection_fkey";

CREATE UNIQUE INDEX in_process_moments_collection_token_id_unique ON public.in_process_moments USING btree (collection, token_id);

ALTER TABLE "public"."in_process_moments"
ADD CONSTRAINT "in_process_moments_collection_token_id_unique" UNIQUE USING index "in_process_moments_collection_token_id_unique";

CREATE TABLE "public"."in_process_sales" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "token" UUID NOT NULL,
  "sale_start" NUMERIC NOT NULL,
  "sale_end" NUMERIC NOT NULL,
  "max_tokens_per_address" NUMERIC NOT NULL,
  "price_per_token" NUMERIC NOT NULL,
  "funds_recipient" TEXT NOT NULL,
  "currency" TEXT NOT NULL
);

ALTER TABLE "public"."in_process_sales" enable ROW level security;

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "chk_in_process_sales_sale_range" CHECK (sale_end >= sale_start);

CREATE UNIQUE INDEX in_process_sales_pkey ON public.in_process_sales USING btree (id);

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_pkey" PRIMARY KEY USING index "in_process_sales_pkey";

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_token_fkey" FOREIGN key (token) REFERENCES public.in_process_tokens (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_sales" validate CONSTRAINT "in_process_sales_token_fkey";

CREATE UNIQUE INDEX in_process_sales_token_unique ON public.in_process_sales USING btree (token);

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_token_unique" UNIQUE USING index "in_process_sales_token_unique";

-- Create trigger function to convert funds_recipient and currency to lowercase
CREATE OR REPLACE FUNCTION "public"."lowercase_in_process_sales_fields" () returns trigger AS $$
begin
    new.funds_recipient := lower(new.funds_recipient);
    new.currency := lower(new.currency);
    return new;
end;
$$ language plpgsql;

-- Create trigger to automatically lowercase funds_recipient and currency on insert/update
CREATE TRIGGER "trg_lowercase_in_process_sales_fields"
BEFORE INSERT OR UPDATE ON "public"."in_process_sales" FOR EACH ROW
EXECUTE FUNCTION "public"."lowercase_in_process_sales_fields" ();
