-- Thread lookup: find replies by parent comment_id.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moment_comments_reply_to_id ON public.in_process_moment_comments (reply_to_id)
WHERE
  reply_to_id IS NOT NULL;
