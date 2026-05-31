alter table "public"."in_process_rooms"
  add column "created_at" timestamp with time zone not null default now();
