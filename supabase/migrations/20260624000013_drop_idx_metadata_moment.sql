-- idx_metadata_moment(moment)
-- Superseded by in_process_metadata_moment_unique UNIQUE(moment):
-- a unique index is a full B-tree index; the planner uses it for all point lookups
-- on moment, making a separate non-unique index on the same column wasteful.
DROP INDEX CONCURRENTLY if EXISTS public.idx_metadata_moment;
