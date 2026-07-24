-- Full unique on comment_id so PostgREST upsert ON CONFLICT (comment_id) works.
-- Postgres UNIQUE still allows multiple NULL comment_id (MintComment).
CREATE UNIQUE INDEX CONCURRENTLY if NOT EXISTS in_process_moment_comments_comment_id_unique_idx ON public.in_process_moment_comments (comment_id);
