-- Drop old function overloads left behind by adding p_mime parameter.
-- CREATE OR REPLACE FUNCTION matches on the full argument type list, so each
-- new 20260312 migration created a new overload instead of replacing the old one.

DROP FUNCTION IF EXISTS public.get_in_process_timeline(integer, integer, numeric, boolean);
DROP FUNCTION IF EXISTS public.get_artist_timeline(text, text, integer, integer, numeric, boolean);
DROP FUNCTION IF EXISTS public.get_collection_timeline(text, integer, integer, numeric, boolean);
