-- Replace btree index on (content->>'mime') with text_pattern_ops variant
-- so that LIKE 'audio/%' patterns can use the index instead of doing a full scan.
DROP INDEX if EXISTS public.in_process_metadata_content_mime_idx;

CREATE INDEX in_process_metadata_content_mime_idx ON public.in_process_metadata USING btree ((content - > > 'mime') text_pattern_ops);
