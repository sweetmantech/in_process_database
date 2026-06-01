create table "public"."in_process_message_moment" (
  "message" uuid not null,
  "moment" uuid not null
);

alter table "public"."in_process_message_moment" enable row level security;

CREATE UNIQUE INDEX in_process_message_moment_message_moment_key ON public.in_process_message_moment USING btree (message, moment);

alter table "public"."in_process_message_moment" add constraint "in_process_message_moment_message_fkey" FOREIGN KEY (message) REFERENCES public.in_process_messages(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_message_moment" validate constraint "in_process_message_moment_message_fkey";

alter table "public"."in_process_message_moment" add constraint "in_process_message_moment_moment_fkey" FOREIGN KEY (moment) REFERENCES public.in_process_moments(id) ON UPDATE CASCADE ON DELETE CASCADE not valid;

alter table "public"."in_process_message_moment" validate constraint "in_process_message_moment_moment_fkey";
