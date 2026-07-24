-- Drop partial unique on comment_id before recreating as a full unique index.
-- Separate file: CREATE INDEX CONCURRENTLY cannot share a pipeline with DROP.
DROP INDEX CONCURRENTLY if EXISTS in_process_moment_comments_comment_id_unique_idx;
