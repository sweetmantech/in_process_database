CREATE TYPE "public"."collection_protocol" AS ENUM('in_process', 'catalog');

ALTER TABLE "public"."in_process_collections"
ADD COLUMN "protocol" collection_protocol NOT NULL DEFAULT 'in_process';
