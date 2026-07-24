-- Nested moment comments for GET /moment/comments.
-- Top-level: one page + replyCount/preview from a single child scan.
-- Reply mode: direct children page only.
CREATE OR REPLACE FUNCTION public.build_moment_comment_json (
  p_id UUID,
  p_comment TEXT,
  p_sender TEXT,
  p_username TEXT,
  p_commented_at TIMESTAMPTZ,
  p_comment_id TEXT,
  p_reply_to_id TEXT,
  p_nonce TEXT,
  p_reply_count INT DEFAULT 0,
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

CREATE OR REPLACE FUNCTION public.get_moment_comments (
  p_moment_id UUID,
  p_offset INT DEFAULT 0,
  p_limit INT DEFAULT 20,
  p_reply_to_id TEXT DEFAULT NULL,
  p_reply_preview INT DEFAULT 3
) returns JSON language plpgsql stable AS $$
DECLARE
  v_offset INT := GREATEST(0, COALESCE(p_offset, 0));
  v_limit INT := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  v_preview INT := GREATEST(0, LEAST(COALESCE(p_reply_preview, 3), 20));
  v_comments JSON;
BEGIN
  IF p_reply_to_id IS NOT NULL THEN
    SELECT COALESCE(
      json_agg(
        public.build_moment_comment_json(
          c.id, c.comment, c.artist_address, a.username, c.commented_at,
          c.comment_id, c.reply_to_id, c.nonce
        )
        ORDER BY c.commented_at ASC
      ),
      '[]'::json
    )
    INTO v_comments
    FROM (
      SELECT c.*
      FROM public.in_process_moment_comments c
      WHERE c.moment = p_moment_id
        AND c.reply_to_id = p_reply_to_id
      ORDER BY c.commented_at ASC
      OFFSET v_offset
      LIMIT v_limit
    ) c
    LEFT JOIN public.in_process_wallets w ON w.address = c.artist_address
    LEFT JOIN public.in_process_artists a ON a.id = w.artist;

    RETURN json_build_object('comments', v_comments);
  END IF;

  WITH top AS MATERIALIZED (
    SELECT
      c.id,
      c.comment,
      c.artist_address,
      c.commented_at,
      c.comment_id,
      c.reply_to_id,
      c.nonce,
      a.username
    FROM public.in_process_moment_comments c
    LEFT JOIN public.in_process_wallets w ON w.address = c.artist_address
    LEFT JOIN public.in_process_artists a ON a.id = w.artist
    WHERE c.moment = p_moment_id
      AND c.reply_to_id IS NULL
    ORDER BY c.commented_at DESC
    OFFSET v_offset
    LIMIT v_limit
  ),
  children AS (
    SELECT
      r.id,
      r.comment,
      r.artist_address,
      r.commented_at,
      r.comment_id,
      r.reply_to_id,
      r.nonce,
      a.username,
      COUNT(*) OVER (PARTITION BY r.reply_to_id) AS reply_count,
      ROW_NUMBER() OVER (
        PARTITION BY r.reply_to_id
        ORDER BY r.commented_at ASC
      ) AS rn
    FROM public.in_process_moment_comments r
    LEFT JOIN public.in_process_wallets w ON w.address = r.artist_address
    LEFT JOIN public.in_process_artists a ON a.id = w.artist
    WHERE r.moment = p_moment_id
      AND r.reply_to_id IN (
        SELECT t.comment_id FROM top t WHERE t.comment_id IS NOT NULL
      )
  ),
  child_agg AS (
    SELECT
      ch.reply_to_id,
      MAX(ch.reply_count) AS reply_count,
      COALESCE(
        json_agg(
          public.build_moment_comment_json(
            ch.id, ch.comment, ch.artist_address, ch.username, ch.commented_at,
            ch.comment_id, ch.reply_to_id, ch.nonce
          )
          ORDER BY ch.commented_at ASC
        ) FILTER (WHERE ch.rn <= v_preview),
        '[]'::json
      ) AS replies
    FROM children ch
    GROUP BY ch.reply_to_id
  )
  SELECT COALESCE(
    json_agg(
      public.build_moment_comment_json(
        t.id, t.comment, t.artist_address, t.username, t.commented_at,
        t.comment_id, t.reply_to_id, t.nonce,
        COALESCE(ca.reply_count, 0),
        COALESCE(ca.replies, '[]'::json)
      )
      ORDER BY t.commented_at DESC
    ),
    '[]'::json
  )
  INTO v_comments
  FROM top t
  LEFT JOIN child_agg ca ON ca.reply_to_id = t.comment_id;

  RETURN json_build_object('comments', v_comments);
END;
$$;
