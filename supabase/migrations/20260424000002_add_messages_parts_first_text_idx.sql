-- GIN trigram index for the nudge cooldown check in get_nudges().
-- The NOT EXISTS subquery uses two LIKE conditions on (parts -> 0 ->> 'text'):
--   LIKE 'Hi! It''s been%'          — prefix match (no leading wildcard)
--   LIKE '%since you last posted%'  — substring match (leading wildcard)
--
-- B-tree + text_pattern_ops only handles prefix LIKE.
-- gin_trgm_ops handles both prefix and substring LIKE, so one index covers both.
-- Requires pg_trgm (already enabled in this project).
-- prettier-ignore
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_messages_parts_first_text_trgm ON public.in_process_messages USING gin ((parts -> 0 ->> 'text') gin_trgm_ops);
