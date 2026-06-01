create table "public"."in_process_metadata" (
  "id" uuid not null default gen_random_uuid(),
  "moment" uuid not null,
  "name" text,
  "description" text,
  "external_url" text,
  "image" text,
  "animation_url" text,
  "content" jsonb,
  "created_at" timestamp with time zone not null default now()
);

alter table "public"."in_process_metadata" enable row level security;

CREATE UNIQUE INDEX in_process_metadata_pkey ON public.in_process_metadata USING btree (id);

alter table "public"."in_process_metadata" add constraint "in_process_metadata_pkey" PRIMARY KEY using index "in_process_metadata_pkey";

alter table "public"."in_process_metadata" add constraint "in_process_metadata_moment_fkey" FOREIGN KEY (moment) REFERENCES public.in_process_moments(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_metadata" validate constraint "in_process_metadata_moment_fkey";

CREATE UNIQUE INDEX in_process_metadata_moment_unique ON public.in_process_metadata USING btree (moment);

alter table "public"."in_process_metadata" add constraint "in_process_metadata_moment_unique" UNIQUE using index "in_process_metadata_moment_unique";

CREATE INDEX in_process_metadata_content_mime_idx ON public.in_process_metadata USING btree ((content->>'mime'));
