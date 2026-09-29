-- Fix: get_video_moments_pending_playback hit statement timeouts and drove
-- Disk IO up (2026-09-28/29).
-- With ORDER BY m.created_at DESC LIMIT n, the planner can walk
-- in_process_moments (~265k rows) newest-first and check each row's metadata
-- until n pending videos turn up. As the backfill marks the newest videos,
-- every run has to walk deeper, reading more metadata from disk each minute.
-- Materialize the ~10k video rows first (mime prefix LIKE uses
-- in_process_metadata_content_mime_idx, text_pattern_ops) so each call does a
-- bounded amount of work regardless of backfill progress.
-- Same signature as 20260929000003 — REPLACE only.
CREATE OR REPLACE FUNCTION public.get_video_moments_pending_playback (p_limit INTEGER DEFAULT 30) returns TABLE (moment UUID, source_uri TEXT) language sql stable AS $$
  WITH videos AS MATERIALIZED (
    SELECT md.moment,
           COALESCE(NULLIF(md.animation_url, ''), md.content->>'uri') AS source_uri
    FROM in_process_metadata md
    WHERE md.content->>'mime' LIKE 'video%'
  )
  SELECT v.moment, v.source_uri
  FROM videos v
  JOIN in_process_moments m ON m.id = v.moment
  WHERE NOT EXISTS (
      SELECT 1 FROM in_process_video_playback p WHERE p.moment = v.moment
    )
    AND v.source_uri NOT ILIKE '%stream.mux.com%'
  ORDER BY m.created_at DESC
  LIMIT GREATEST(0, LEAST(COALESCE(p_limit, 30), 200))
$$;
