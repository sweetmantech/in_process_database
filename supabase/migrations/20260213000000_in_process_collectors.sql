create table "public"."in_process_collectors" (
    "id" uuid not null default gen_random_uuid(),
    "collector" text not null,
    "moment" uuid not null,
    "amount" numeric not null,
    "transaction_hash" text not null,
    "collected_at" timestamp with time zone not null default now()
);

alter table "public"."in_process_collectors" enable row level security;

CREATE UNIQUE INDEX in_process_collectors_pkey ON public.in_process_collectors USING btree (id);

alter table "public"."in_process_collectors" add constraint "in_process_collectors_pkey" PRIMARY KEY using index "in_process_collectors_pkey";

alter table "public"."in_process_collectors" add constraint "in_process_collectors_moment_fkey" FOREIGN KEY (moment) REFERENCES public.in_process_moments(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_collectors" validate constraint "in_process_collectors_moment_fkey";

alter table "public"."in_process_collectors" add constraint "in_process_collectors_collector_fkey" FOREIGN KEY (collector) REFERENCES public.in_process_artists(address) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_collectors" validate constraint "in_process_collectors_collector_fkey";

CREATE UNIQUE INDEX in_process_collectors_collector_transaction_moment_idx ON public.in_process_collectors USING btree (collector, transaction_hash, moment);

CREATE INDEX in_process_collectors_moment_collector_idx ON public.in_process_collectors USING btree (moment, collector);
