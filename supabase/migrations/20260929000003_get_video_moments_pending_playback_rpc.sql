-- Video moments that still need a streaming playback copy (Mux), newest first.
-- Used by the api's Mux ingest cron (backfill + auto-ingest of new videos).
-- - Only moments with no in_process_video_playback row (ready, preparing or
--   errored rows are all excluded, so failures are not retried forever).
-- - Skips sources still on stream.mux.com: fresh uploads get their row from
--   the Arweave migration workflow; the rest point at deleted assets.
-- The prefix LIKE on mime uses in_process_metadata_content_mime_idx
-- (text_pattern_ops, 20260408020000), so only the ~10k video rows are read.
CREATE OR REPLACE FUNCTION public.get_video_moments_pending_playback (p_limit INTEGER DEFAULT 30) returns TABLE (moment UUID, source_uri TEXT) language sql stable AS $$
  SELECT md.moment, COALESCE(NULLIF(md.animation_url, ''), md.content->>'uri') AS source_uri
  FROM in_process_metadata md
  JOIN in_process_moments m ON m.id = md.moment
  WHERE md.content->>'mime' LIKE 'video%'
    AND NOT EXISTS (
      SELECT 1 FROM in_process_video_playback v WHERE v.moment = md.moment
    )
    AND COALESCE(NULLIF(md.animation_url, ''), md.content->>'uri') NOT ILIKE '%stream.mux.com%'
  ORDER BY m.created_at DESC
  LIMIT GREATEST(0, LEAST(COALESCE(p_limit, 30), 200))
$$;
