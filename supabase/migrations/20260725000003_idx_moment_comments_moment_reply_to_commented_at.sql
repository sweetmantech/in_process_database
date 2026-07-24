-- Speeds get_moment_comments reply mode / child lookup: moment + reply_to_id + time order.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moment_comments_moment_reply_to_commented_at ON public.in_process_moment_comments (moment, reply_to_id, commented_at ASC)
WHERE
  reply_to_id IS NOT NULL;
