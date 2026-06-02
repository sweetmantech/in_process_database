-- Replace in_process_notifications.payment (FK → in_process_payments)
-- with transfer (FK → in_process_transfers).

-- Drop old unique constraint and index
ALTER TABLE in_process_notifications
  DROP CONSTRAINT IF EXISTS unique_payment_artist;

DROP INDEX IF EXISTS idx_in_process_notifications_payment;

-- Drop old payment column (cascades FK)
ALTER TABLE in_process_notifications
  DROP COLUMN IF EXISTS payment;

-- Add new transfer column
ALTER TABLE in_process_notifications
  ADD COLUMN transfer uuid NOT NULL REFERENCES in_process_transfers(id) ON DELETE CASCADE;

-- Unique constraint: one notification per transfer per artist
ALTER TABLE in_process_notifications
  ADD CONSTRAINT unique_transfer_artist UNIQUE (transfer, artist);

-- Index for FK lookups on transfer
CREATE INDEX idx_in_process_notifications_transfer
  ON in_process_notifications(transfer);

-- Update table comment
COMMENT ON TABLE in_process_notifications
  IS 'Notifications for paid transfer events in the in-process system';
COMMENT ON COLUMN in_process_notifications.transfer
  IS 'Foreign key reference to in_process_transfers table';
