-- Drop old function overload left behind by adding p_mime parameter.
-- CREATE OR REPLACE FUNCTION matches on the full argument type list, so the
-- previous migration created a new overload instead of replacing the old one.
DROP FUNCTION if EXISTS public.get_in_process_payments (INTEGER, INTEGER, TEXT[], TEXT[], NUMERIC);
