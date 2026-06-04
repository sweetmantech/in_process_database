CREATE TABLE "public"."in_process_collection_admins" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "collection" UUID NOT NULL,
  "artist_address" TEXT NOT NULL,
  "granted_at" TIMESTAMP WITH TIME ZONE NOT NULL,
  "hidden" BOOLEAN NOT NULL DEFAULT FALSE
);

ALTER TABLE "public"."in_process_collection_admins" enable ROW level security;

CREATE UNIQUE INDEX in_process_collection_admins_pkey ON public.in_process_collection_admins USING btree (id);

ALTER TABLE "public"."in_process_collection_admins"
ADD CONSTRAINT "in_process_collection_admins_pkey" PRIMARY KEY USING index "in_process_collection_admins_pkey";

ALTER TABLE "public"."in_process_collection_admins"
ADD CONSTRAINT "in_process_collection_admins_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_collection_admins" validate CONSTRAINT "in_process_collection_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_collection_admins"
ADD CONSTRAINT "in_process_collection_admins_collection_fkey" FOREIGN key (collection) REFERENCES public.in_process_collections (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_collection_admins" validate CONSTRAINT "in_process_collection_admins_collection_fkey";

CREATE UNIQUE INDEX in_process_collection_admins_collection_artist_address_unique ON public.in_process_collection_admins USING btree (collection, artist_address);
