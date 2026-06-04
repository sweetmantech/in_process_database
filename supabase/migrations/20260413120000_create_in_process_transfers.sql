CREATE TABLE public.in_process_transfers (
  id TEXT NOT NULL PRIMARY KEY,
  recipient TEXT NOT NULL,
  quantity TEXT NOT NULL,
  value TEXT,
  currency TEXT,
  transaction_hash TEXT NOT NULL,
  transferred_at TIMESTAMP WITH TIME ZONE NOT NULL,
  moment UUID NOT NULL REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX idx_in_process_transfers_transferred_at_desc ON public.in_process_transfers USING btree (transferred_at DESC);

CREATE INDEX idx_in_process_transfers_moment ON public.in_process_transfers USING btree (moment);

CREATE UNIQUE INDEX in_process_transfers_recipient_transaction_moment_idx ON public.in_process_transfers USING btree (recipient, transaction_hash, moment);

ALTER TABLE public.in_process_transfers enable ROW level security;
