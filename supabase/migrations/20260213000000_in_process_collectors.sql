CREATE TABLE "public"."in_process_collectors" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "collector" TEXT NOT NULL,
  "moment" UUID NOT NULL,
  "amount" NUMERIC NOT NULL,
  "transaction_hash" TEXT NOT NULL,
  "collected_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_collectors" enable ROW level security;

CREATE UNIQUE INDEX in_process_collectors_pkey ON public.in_process_collectors USING btree (id);

ALTER TABLE "public"."in_process_collectors"
ADD CONSTRAINT "in_process_collectors_pkey" PRIMARY KEY USING index "in_process_collectors_pkey";

ALTER TABLE "public"."in_process_collectors"
ADD CONSTRAINT "in_process_collectors_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_collectors" validate CONSTRAINT "in_process_collectors_moment_fkey";

ALTER TABLE "public"."in_process_collectors"
ADD CONSTRAINT "in_process_collectors_collector_fkey" FOREIGN key (collector) REFERENCES public.in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_collectors" validate CONSTRAINT "in_process_collectors_collector_fkey";

CREATE UNIQUE INDEX in_process_collectors_collector_transaction_moment_idx ON public.in_process_collectors USING btree (collector, transaction_hash, moment);

CREATE INDEX in_process_collectors_moment_collector_idx ON public.in_process_collectors USING btree (moment, collector);
