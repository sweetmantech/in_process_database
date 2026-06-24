-- Drop hidden column from in_process_admins.
-- get_creator_hidden and moment_is_visible were dropped in 20260624000002.
-- hide/show is now managed exclusively via in_process_hidden table.
ALTER TABLE public.in_process_admins
DROP COLUMN hidden;
