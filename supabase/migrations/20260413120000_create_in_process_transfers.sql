CREATE TABLE public.in_process_transfers (
  id text NOT NULL PRIMARY KEY,
  recipient text NOT NULL,
  quantity text NOT NULL,
  value text,
  currency text,
  transaction_hash text NOT NULL,
  transferred_at timestamp with time zone NOT NULL,
  moment uuid NOT NULL REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE
);

CREATE INDEX idx_in_process_transfers_transferred_at_desc
  ON public.in_process_transfers USING btree (transferred_at DESC);

CREATE INDEX idx_in_process_transfers_moment
  ON public.in_process_transfers USING btree (moment);

CREATE UNIQUE INDEX in_process_transfers_recipient_transaction_moment_idx
  ON public.in_process_transfers USING btree (recipient, transaction_hash, moment);

ALTER TABLE public.in_process_transfers ENABLE ROW LEVEL SECURITY;