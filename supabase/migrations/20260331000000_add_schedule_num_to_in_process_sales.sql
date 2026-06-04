ALTER TABLE "public"."in_process_sales"
ADD COLUMN "schedule_num" INTEGER DEFAULT NULL;

ALTER TABLE "public"."in_process_sales"
DROP CONSTRAINT if EXISTS "in_process_sales_moment_unique";

DROP INDEX if EXISTS "public"."in_process_sales_moment_unique";

CREATE UNIQUE INDEX in_process_sales_moment_schedule_num_unique ON public.in_process_sales USING btree (moment, schedule_num);

ALTER TABLE "public"."in_process_sales"
ADD CONSTRAINT "in_process_sales_moment_schedule_num_unique" UNIQUE USING index "in_process_sales_moment_schedule_num_unique";
