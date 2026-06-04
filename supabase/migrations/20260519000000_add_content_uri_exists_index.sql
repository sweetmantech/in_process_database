-- prettier-ignore
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_in_process_metadata_content_uri_exists ON public.in_process_metadata (moment)
WHERE
  content ->> 'uri' IS NOT NULL
  AND content ->> 'uri' != '';
