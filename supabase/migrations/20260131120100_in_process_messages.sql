-- Create enum type for message role
CREATE TYPE message_role AS ENUM('user', 'assistant');

CREATE TABLE "public"."in_process_messages" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "role" message_role NOT NULL,
  "parts" JSONB NOT NULL,
  "metadata" UUID NOT NULL
);

ALTER TABLE "public"."in_process_messages" enable ROW level security;

CREATE UNIQUE INDEX in_process_messages_pkey ON public.in_process_messages USING btree (id);

ALTER TABLE "public"."in_process_messages"
ADD CONSTRAINT "in_process_messages_pkey" PRIMARY KEY USING index "in_process_messages_pkey";

ALTER TABLE "public"."in_process_messages"
ADD CONSTRAINT "in_process_messages_metadata_fkey" FOREIGN key (metadata) REFERENCES public.in_process_message_metadata (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_messages" validate CONSTRAINT "in_process_messages_metadata_fkey";
