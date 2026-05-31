alter table "public"."in_process_sales" drop constraint if exists "in_process_sales_moment_schedule_num_unique";

drop index if exists "public"."in_process_sales_moment_schedule_num_unique";

alter table "public"."in_process_sales" drop column if exists "schedule_num";

CREATE UNIQUE INDEX in_process_sales_moment_unique ON public.in_process_sales USING btree (moment);

alter table "public"."in_process_sales" add constraint "in_process_sales_moment_unique" UNIQUE using index "in_process_sales_moment_unique";
