CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_in_process_message_moment_on_moment
  ON public.in_process_message_moment (moment, message);
