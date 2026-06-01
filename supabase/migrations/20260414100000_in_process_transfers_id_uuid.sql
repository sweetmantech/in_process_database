-- Replace text primary key with uuid (new id per row; old text id discarded).

ALTER TABLE public.in_process_transfers
  ADD COLUMN temp_id uuid NOT NULL DEFAULT gen_random_uuid();

ALTER TABLE public.in_process_transfers
  DROP CONSTRAINT in_process_transfers_pkey;

ALTER TABLE public.in_process_transfers
  ADD CONSTRAINT in_process_transfers_pkey PRIMARY KEY (temp_id);

ALTER TABLE public.in_process_transfers
  DROP COLUMN id;

ALTER TABLE public.in_process_transfers
  RENAME COLUMN temp_id TO id;
