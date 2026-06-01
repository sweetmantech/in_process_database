create table "public"."in_process_rooms" (
  "id" text not null -- chat/channel identifier (e.g. Telegram chat_id). Typed as text to stay client-agnostic and extend to other platforms without schema changes.
);

alter table "public"."in_process_rooms" enable row level security;

CREATE UNIQUE INDEX in_process_rooms_pkey ON public.in_process_rooms USING btree (id);

alter table "public"."in_process_rooms" add constraint "in_process_rooms_pkey" PRIMARY KEY using index "in_process_rooms_pkey";

alter table "public"."in_process_messages"
  add column "room" text null default null;

alter table "public"."in_process_messages"
  add constraint "in_process_messages_room_fkey"
  FOREIGN KEY (room) REFERENCES public.in_process_rooms(id)
  ON UPDATE CASCADE ON DELETE SET NULL not valid;

alter table "public"."in_process_messages"
  validate constraint "in_process_messages_room_fkey";

CREATE INDEX idx_in_process_messages_room
  ON public.in_process_messages USING btree (room);
