-- Create enum type for message role
CREATE TYPE message_role AS ENUM ('user', 'assistant');

create table "public"."in_process_messages" (
  "id" uuid not null default gen_random_uuid(),
  "role" message_role not null,
  "parts" jsonb not null,
  "metadata" uuid not null
);

alter table "public"."in_process_messages" enable row level security;

CREATE UNIQUE INDEX in_process_messages_pkey ON public.in_process_messages USING btree (id);

alter table "public"."in_process_messages" add constraint "in_process_messages_pkey" PRIMARY KEY using index "in_process_messages_pkey";

alter table "public"."in_process_messages" add constraint "in_process_messages_metadata_fkey" FOREIGN KEY (metadata) REFERENCES public.in_process_message_metadata(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_messages" validate constraint "in_process_messages_metadata_fkey";
