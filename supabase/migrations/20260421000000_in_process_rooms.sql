CREATE TABLE "public"."in_process_rooms" (
  "id" TEXT NOT NULL -- chat/channel identifier (e.g. Telegram chat_id). Typed as text to stay client-agnostic and extend to other platforms without schema changes.
);

ALTER TABLE "public"."in_process_rooms" enable ROW level security;

CREATE UNIQUE INDEX in_process_rooms_pkey ON public.in_process_rooms USING btree (id);

ALTER TABLE "public"."in_process_rooms"
ADD CONSTRAINT "in_process_rooms_pkey" PRIMARY KEY USING index "in_process_rooms_pkey";

ALTER TABLE "public"."in_process_messages"
ADD COLUMN "room" TEXT NULL DEFAULT NULL;

ALTER TABLE "public"."in_process_messages"
ADD CONSTRAINT "in_process_messages_room_fkey" FOREIGN key (room) REFERENCES public.in_process_rooms (id) ON UPDATE CASCADE ON DELETE SET NULL NOT valid;

ALTER TABLE "public"."in_process_messages" validate CONSTRAINT "in_process_messages_room_fkey";

CREATE INDEX idx_in_process_messages_room ON public.in_process_messages USING btree (room);
