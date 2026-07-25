-- Speeds get_moment_comments top-level page: moment + reply_to_id IS NULL + commented_at DESC.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moment_comments_moment_top_commented_at_desc ON public.in_process_moment_comments (moment, commented_at DESC)
WHERE
  reply_to_id IS NULL;
