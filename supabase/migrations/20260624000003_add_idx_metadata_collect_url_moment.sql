-- Partial index on in_process_metadata(moment) for rows where external_url
-- matches the Zora collect link pattern ('%/collect/base:%/%').
--
-- Why partial: only a small fraction of metadata rows have this URL pattern,
-- so the index stays small while covering the exact predicate used in
-- NOT EXISTS checks across all get_in_process_timeline branches:
--
--   NOT EXISTS (
--     SELECT 1 FROM in_process_metadata meta2
--     WHERE meta2.moment = m.id
--       AND meta2.external_url LIKE '%/collect/base:%/%'
--   )
--
-- PostgreSQL recognises that the partial index WHERE clause matches the query
-- condition, so the NOT EXISTS reduces to a single index point-lookup on
-- moment instead of a per-row sequential scan of in_process_metadata.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_metadata_collect_url_moment ON public.in_process_metadata (moment)
WHERE
  external_url LIKE '%/collect/base:%/%';
