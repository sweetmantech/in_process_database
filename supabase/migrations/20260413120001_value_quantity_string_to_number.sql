ALTER TABLE "public"."in_process_transfers"
ALTER COLUMN quantity type NUMERIC USING (quantity::NUMERIC),
ALTER COLUMN value type NUMERIC USING (value::NUMERIC);
