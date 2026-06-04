-- Reusable channel filter: matches moments by message client or 'web' (no message)
CREATE OR REPLACE FUNCTION public.moment_matches_channel (p_moment_id UUID, p_channel TEXT) returns BOOLEAN language sql stable AS $$
  SELECT
    p_channel IS NULL
    OR EXISTS (
      SELECT 1
      FROM in_process_message_moment mm
      INNER JOIN in_process_messages msg ON msg.id = mm.message
      INNER JOIN in_process_message_metadata mmd ON mmd.id = msg.metadata
      WHERE mm.moment = p_moment_id
        AND mmd.client::text = p_channel
    )
    OR (
      p_channel = 'web'
      AND NOT EXISTS (
        SELECT 1
        FROM in_process_message_moment mm
        INNER JOIN in_process_messages msg ON msg.id = mm.message
        INNER JOIN in_process_message_metadata mmd ON mmd.id = msg.metadata
        WHERE mm.moment = p_moment_id
      )
    )
$$;

-- accidentally filtering to only moments from "right now" (INTERVAL '0').
CREATE OR REPLACE FUNCTION public.moment_matches_period (p_created_at TIMESTAMPTZ, p_period TEXT) returns BOOLEAN language sql stable AS $$
  SELECT
    p_period IS NULL
    OR p_period = 'all'
    OR (
      CASE p_period
        WHEN 'day'   THEN INTERVAL '1 day'
        WHEN 'week'  THEN INTERVAL '7 days'
        WHEN 'month' THEN INTERVAL '30 days'
        ELSE NULL::interval
      END
    ) IS NOT NULL
    AND p_created_at >= NOW() - CASE p_period
      WHEN 'day'   THEN INTERVAL '1 day'
      WHEN 'week'  THEN INTERVAL '7 days'
      WHEN 'month' THEN INTERVAL '30 days'
      ELSE NULL::interval
    END
$$;
