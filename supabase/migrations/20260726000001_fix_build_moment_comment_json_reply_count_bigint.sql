-- COUNT(*) OVER returns bigint; build_moment_comment_json used INT for
-- p_reply_count, so the 10-arg call failed to resolve at runtime.
DROP FUNCTION if EXISTS public.build_moment_comment_json (
  UUID,
  TEXT,
  TEXT,
  TEXT,
  TIMESTAMPTZ,
  TEXT,
  TEXT,
  TEXT,
  INT,
  JSON
);

CREATE OR REPLACE FUNCTION public.build_moment_comment_json (
  p_id UUID,
  p_comment TEXT,
  p_sender TEXT,
  p_username TEXT,
  p_commented_at TIMESTAMPTZ,
  p_comment_id TEXT,
  p_reply_to_id TEXT,
  p_nonce TEXT,
  p_reply_count BIGINT DEFAULT 0,
  p_replies JSON DEFAULT '[]'::JSON
) returns JSON language sql stable AS $$
  SELECT json_build_object(
    'id', p_id,
    'comment', COALESCE(p_comment, ''),
    'sender', p_sender,
    'username', COALESCE(p_username, ''),
    'timestamp', CASE
      WHEN p_commented_at IS NULL THEN 0
      ELSE (EXTRACT(EPOCH FROM p_commented_at) * 1000)::BIGINT
    END,
    'commentId', p_comment_id,
    'replyToId', p_reply_to_id,
    'nonce', p_nonce,
    'replyCount', COALESCE(p_reply_count, 0),
    'replies', COALESCE(p_replies, '[]'::json)
  );
$$;
