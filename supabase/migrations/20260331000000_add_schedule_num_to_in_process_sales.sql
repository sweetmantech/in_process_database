alter table "public"."in_process_sales"
  add column "schedule_num" integer default null;

alter table "public"."in_process_sales" drop constraint if exists "in_process_sales_moment_unique";

drop index if exists "public"."in_process_sales_moment_unique";

CREATE UNIQUE INDEX in_process_sales_moment_schedule_num_unique ON public.in_process_sales USING btree (moment, schedule_num);

alter table "public"."in_process_sales" add constraint "in_process_sales_moment_schedule_num_unique" UNIQUE using index "in_process_sales_moment_schedule_num_unique";
