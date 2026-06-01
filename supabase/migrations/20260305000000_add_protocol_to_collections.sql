create type "public"."collection_protocol" as enum ('in_process', 'catalog');

alter table "public"."in_process_collections"
  add column "protocol" collection_protocol not null default 'in_process';
