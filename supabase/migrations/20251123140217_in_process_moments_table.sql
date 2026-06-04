CREATE TABLE "public"."in_process_moments" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "collection_id" UUID NOT NULL,
  "token_id" NUMERIC NOT NULL,
  "uri" TEXT NOT NULL,
  "max_supply" NUMERIC NOT NULL,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL
);

ALTER TABLE "public"."in_process_moments" enable ROW level security;

CREATE UNIQUE INDEX in_process_moments_pkey ON public.in_process_moments USING btree (id);

ALTER TABLE "public"."in_process_moments"
ADD CONSTRAINT "in_process_moments_pkey" PRIMARY KEY USING index "in_process_moments_pkey";

ALTER TABLE "public"."in_process_moments"
ADD CONSTRAINT "in_process_moments_collection_id_fkey" FOREIGN key (collection_id) REFERENCES public.in_process_collections (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_moments" validate CONSTRAINT "in_process_moments_collection_id_fkey";

CREATE UNIQUE INDEX in_process_moments_collection_id_token_id_unique ON public.in_process_moments USING btree (collection_id, token_id);

ALTER TABLE "public"."in_process_moments"
ADD CONSTRAINT "in_process_moments_collection_id_token_id_unique" UNIQUE USING index "in_process_moments_collection_id_token_id_unique";
