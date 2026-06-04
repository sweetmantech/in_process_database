ALTER TABLE public.in_process_artists
ADD COLUMN notify_enabled BOOLEAN NOT NULL DEFAULT FALSE;
