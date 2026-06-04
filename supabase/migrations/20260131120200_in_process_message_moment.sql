CREATE TABLE "public"."in_process_message_moment" ("message" UUID NOT NULL, "moment" UUID NOT NULL);

ALTER TABLE "public"."in_process_message_moment" enable ROW level security;

CREATE UNIQUE INDEX in_process_message_moment_message_moment_key ON public.in_process_message_moment USING btree (message, moment);

ALTER TABLE "public"."in_process_message_moment"
ADD CONSTRAINT "in_process_message_moment_message_fkey" FOREIGN key (message) REFERENCES public.in_process_messages (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_message_moment" validate CONSTRAINT "in_process_message_moment_message_fkey";

ALTER TABLE "public"."in_process_message_moment"
ADD CONSTRAINT "in_process_message_moment_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_message_moment" validate CONSTRAINT "in_process_message_moment_moment_fkey";
