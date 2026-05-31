ALTER TABLE "public"."in_process_transfers" 
  ALTER COLUMN quantity TYPE numeric USING (quantity::numeric),
  ALTER COLUMN value TYPE numeric USING (value::numeric);