CREATE TABLE "public"."in_process_artist_phones" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "artist_address" TEXT NOT NULL,
  "phone_number" TEXT NOT NULL,
  "verified" BOOLEAN NOT NULL DEFAULT FALSE,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_artist_phones" enable ROW level security;

CREATE UNIQUE INDEX in_process_artist_phones_pkey ON public.in_process_artist_phones USING btree (id);

ALTER TABLE "public"."in_process_artist_phones"
ADD CONSTRAINT "in_process_artist_phones_pkey" PRIMARY KEY USING index "in_process_artist_phones_pkey";

ALTER TABLE "public"."in_process_artist_phones"
ADD CONSTRAINT "in_process_artist_phones_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_artist_phones" validate CONSTRAINT "in_process_artist_phones_artist_address_fkey";
