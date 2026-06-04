CREATE TABLE "public"."in_process_airdrops" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "artist_address" TEXT NOT NULL,
  "amount" NUMERIC NOT NULL,
  "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "moment" UUID NOT NULL
);

ALTER TABLE "public"."in_process_airdrops" enable ROW level security;

CREATE UNIQUE INDEX in_process_airdrops_pkey ON public.in_process_airdrops USING btree (id);

ALTER TABLE "public"."in_process_airdrops"
ADD CONSTRAINT "in_process_airdrops_pkey" PRIMARY KEY USING index "in_process_airdrops_pkey";

ALTER TABLE "public"."in_process_airdrops"
ADD CONSTRAINT "in_process_airdrops_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_airdrops" validate CONSTRAINT "in_process_airdrops_artist_address_fkey";

ALTER TABLE "public"."in_process_airdrops"
ADD CONSTRAINT "in_process_airdrops_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_airdrops" validate CONSTRAINT "in_process_airdrops_moment_fkey";

CREATE INDEX in_process_airdrops_moment_artist_address_idx ON public.in_process_airdrops USING btree (moment, artist_address);
