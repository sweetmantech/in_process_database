CREATE TABLE "public"."in_process_moment_admins" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "moment" UUID NOT NULL,
  "artist_address" TEXT NOT NULL,
  "hidden" BOOLEAN NOT NULL DEFAULT FALSE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE "public"."in_process_moment_admins" enable ROW level security;

CREATE UNIQUE INDEX in_process_moment_admins_pkey ON public.in_process_moment_admins USING btree (id);

ALTER TABLE "public"."in_process_moment_admins"
ADD CONSTRAINT "in_process_moment_admins_pkey" PRIMARY KEY USING index "in_process_moment_admins_pkey";

ALTER TABLE "public"."in_process_moment_admins"
ADD CONSTRAINT "in_process_moment_admins_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moment_admins" validate CONSTRAINT "in_process_moment_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_moment_admins"
ADD CONSTRAINT "in_process_moment_admins_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moment_admins" validate CONSTRAINT "in_process_moment_admins_moment_fkey";

CREATE UNIQUE INDEX in_process_moment_admins_moment_artist_address_unique ON public.in_process_moment_admins USING btree (moment, artist_address);
