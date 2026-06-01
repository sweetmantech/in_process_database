ALTER TABLE public.in_process_artists
  ADD COLUMN nudge_enabled boolean NOT NULL DEFAULT false;
