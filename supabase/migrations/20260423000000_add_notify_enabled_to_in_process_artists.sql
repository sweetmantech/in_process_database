ALTER TABLE public.in_process_artists
  ADD COLUMN notify_enabled boolean NOT NULL DEFAULT false;
