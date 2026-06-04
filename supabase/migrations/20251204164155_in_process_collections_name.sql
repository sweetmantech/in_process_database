ALTER TABLE "public"."in_process_collections"
ADD COLUMN "name" TEXT NOT NULL DEFAULT ''::TEXT;
