-- Derived media outputs in Supabase Storage (resized images, later streams/thumbs, etc.).
-- Storage holds bytes; this table holds TTL metadata for cron cleanup.
CREATE TABLE "public"."in_process_media_cache" (
  "hash" TEXT NOT NULL,
  "path" TEXT NOT NULL,
  "kind" TEXT NOT NULL DEFAULT 'image',
  "created_at" TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  "updated_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_media_cache" enable ROW level security;

CREATE UNIQUE INDEX in_process_media_cache_pkey ON public.in_process_media_cache USING btree (hash);

ALTER TABLE "public"."in_process_media_cache"
ADD CONSTRAINT "in_process_media_cache_pkey" PRIMARY KEY USING index "in_process_media_cache_pkey";

CREATE INDEX idx_media_cache_created_at ON public.in_process_media_cache USING btree (created_at);
