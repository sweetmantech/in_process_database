-- Drop old function overloads left behind by adding p_mime parameter.
-- CREATE OR REPLACE FUNCTION matches on the full argument type list, so each
-- new 20260312 migration created a new overload instead of replacing the old one.
DROP FUNCTION if EXISTS public.get_in_process_timeline (INTEGER, INTEGER, NUMERIC, BOOLEAN);

DROP FUNCTION if EXISTS public.get_artist_timeline (TEXT, TEXT, INTEGER, INTEGER, NUMERIC, BOOLEAN);

DROP FUNCTION if EXISTS public.get_collection_timeline (TEXT, INTEGER, INTEGER, NUMERIC, BOOLEAN);
