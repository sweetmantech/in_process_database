-- Index for build_moment_json comments count: moment-first lookup on in_process_moment_comments.
-- Existing in_process_moment_comments_artist_commented_at_moment_unique_idx leads with
-- artist_address, so WHERE moment = ? cannot use it efficiently.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_moment_comments_moment_commented_at_desc ON public.in_process_moment_comments (moment, commented_at DESC);
