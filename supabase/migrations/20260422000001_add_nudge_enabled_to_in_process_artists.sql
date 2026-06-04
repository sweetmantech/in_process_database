ALTER TABLE public.in_process_artists
ADD COLUMN nudge_enabled BOOLEAN NOT NULL DEFAULT FALSE;
