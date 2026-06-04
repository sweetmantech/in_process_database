CREATE TABLE "public"."in_process_metadata" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "moment" UUID NOT NULL,
  "name" TEXT,
  "description" TEXT,
  "external_url" TEXT,
  "image" TEXT,
  "animation_url" TEXT,
  "content" JSONB,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_metadata" enable ROW level security;

CREATE UNIQUE INDEX in_process_metadata_pkey ON public.in_process_metadata USING btree (id);

ALTER TABLE "public"."in_process_metadata"
ADD CONSTRAINT "in_process_metadata_pkey" PRIMARY KEY USING index "in_process_metadata_pkey";

ALTER TABLE "public"."in_process_metadata"
ADD CONSTRAINT "in_process_metadata_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_metadata" validate CONSTRAINT "in_process_metadata_moment_fkey";

CREATE UNIQUE INDEX in_process_metadata_moment_unique ON public.in_process_metadata USING btree (moment);

ALTER TABLE "public"."in_process_metadata"
ADD CONSTRAINT "in_process_metadata_moment_unique" UNIQUE USING index "in_process_metadata_moment_unique";

-- prettier-ignore
CREATE INDEX in_process_metadata_content_mime_idx ON public.in_process_metadata USING btree ((content ->> 'mime'));
