ALTER TABLE "public"."in_process_sales"
DROP CONSTRAINT if EXISTS "in_process_sales_moment_schedule_num_unique";

DROP INDEX if EXISTS "public"."in_process_sales_moment_schedule_num_unique";

ALTER TABLE "public"."in_process_sales"
DROP COLUMN IF EXISTS "schedule_num";

CREATE UNIQUE INDEX in_process_sales_moment_unique ON public.in_process_sales USING btree (moment);

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_moment_unique" UNIQUE USING index "in_process_sales_moment_unique";
