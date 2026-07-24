-- Deduplicate protocol comments by Zora commentId (MintComment rows have NULL).
CREATE UNIQUE INDEX CONCURRENTLY if NOT EXISTS in_process_moment_comments_comment_id_unique_idx ON public.in_process_moment_comments (comment_id)
WHERE
  comment_id IS NOT NULL;
