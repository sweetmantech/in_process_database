CREATE TABLE "public"."in_process_moment_comments" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "comment" TEXT,
  "moment" UUID NOT NULL,
  "artist_address" TEXT NOT NULL DEFAULT ''::TEXT,
  "commented_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_moment_comments" enable ROW level security;

ALTER TABLE "public"."in_process_collections"
ADD COLUMN "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL;

ALTER TABLE "public"."in_process_moment_admins"
DROP COLUMN "created_at";

ALTER TABLE "public"."in_process_moment_admins"
ADD COLUMN "granted_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW();

ALTER TABLE "public"."in_process_moments"
ADD COLUMN "updated_at" TIMESTAMP WITH TIME ZONE NOT NULL;

CREATE UNIQUE INDEX in_process_moment_comments_pkey ON public.in_process_moment_comments USING btree (id);

ALTER TABLE "public"."in_process_moment_comments"
ADD CONSTRAINT "in_process_moment_comments_pkey" PRIMARY KEY USING index "in_process_moment_comments_pkey";

ALTER TABLE "public"."in_process_moment_comments"
ADD CONSTRAINT "in_process_moment_comments_artist_address_fkey" FOREIGN key (artist_address) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moment_comments" validate CONSTRAINT "in_process_moment_comments_artist_address_fkey";

ALTER TABLE "public"."in_process_moment_comments"
ADD CONSTRAINT "in_process_moment_comments_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moment_comments" validate CONSTRAINT "in_process_moment_comments_moment_fkey";
