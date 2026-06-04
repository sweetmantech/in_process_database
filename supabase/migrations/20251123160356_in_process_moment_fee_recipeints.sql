CREATE TABLE "public"."in_process_moment_fee_recipients" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "moment" UUID NOT NULL,
  "artist_address" TEXT NOT NULL,
  "percent_allocation" NUMERIC NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_moment_fee_recipients" enable ROW level security;

ALTER TABLE "public"."in_process_moment_admins"
ALTER COLUMN "created_at"
SET DEFAULT NOW();

ALTER TABLE "public"."in_process_sales"
ADD COLUMN "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();

CREATE UNIQUE INDEX in_process_moment_fee_recipients_pkey ON public.in_process_moment_fee_recipients USING btree (id);

ALTER TABLE "public"."in_process_moment_fee_recipients"
ADD CONSTRAINT "in_process_moment_fee_recipients_pkey" PRIMARY KEY USING index "in_process_moment_fee_recipients_pkey";

ALTER TABLE "public"."in_process_moment_fee_recipients"
ADD CONSTRAINT "in_process_moment_fee_recipients_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE RESTRICT NOT valid;

ALTER TABLE "public"."in_process_moment_fee_recipients" validate CONSTRAINT "in_process_moment_fee_recipients_artist_address_fkey";

ALTER TABLE "public"."in_process_moment_fee_recipients"
ADD CONSTRAINT "in_process_moment_fee_recipients_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moment_fee_recipients" validate CONSTRAINT "in_process_moment_fee_recipients_moment_fkey";

CREATE UNIQUE INDEX in_process_moment_fee_recipients_moment_artist_address_unique ON public.in_process_moment_fee_recipients USING btree (moment, artist_address);

ALTER TABLE "public"."in_process_collections"
DROP CONSTRAINT "in_process_collections_default_admin_fkey";

ALTER TABLE "public"."in_process_moment_admins"
DROP CONSTRAINT "in_process_moment_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_collections"
ADD CONSTRAINT "in_process_collections_default_admin_fkey" FOREIGN key (default_admin) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE RESTRICT NOT valid;

ALTER TABLE "public"."in_process_collections" validate CONSTRAINT "in_process_collections_default_admin_fkey";

ALTER TABLE "public"."in_process_moment_admins"
ADD CONSTRAINT "in_process_moment_admins_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE RESTRICT NOT valid;

ALTER TABLE "public"."in_process_moment_admins" validate CONSTRAINT "in_process_moment_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_sales"
DROP CONSTRAINT "in_process_sales_token_fkey";

ALTER TABLE "public"."in_process_sales"
DROP CONSTRAINT "in_process_sales_token_unique";

DROP INDEX if EXISTS "public"."in_process_sales_token_unique";

ALTER TABLE "public"."in_process_sales"
DROP COLUMN "token";

ALTER TABLE "public"."in_process_sales"
ADD COLUMN "moment" UUID NOT NULL;

CREATE UNIQUE INDEX in_process_sales_moment_unique ON public.in_process_sales USING btree (moment);

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_sales" validate CONSTRAINT "in_process_sales_moment_fkey";

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_moment_unique" UNIQUE USING index "in_process_sales_moment_unique";
