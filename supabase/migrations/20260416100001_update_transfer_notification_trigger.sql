-- Replace the payment-based notification trigger with a transfer-based one.
-- A notification is created for the moment's creator whenever a transfer
-- with value > 0 is inserted into in_process_transfers.

-- Drop old trigger and function
DROP TRIGGER IF EXISTS payment_notification_trigger ON in_process_payments;
DROP FUNCTION IF EXISTS create_payment_notification();

-- Create new trigger function
CREATE OR REPLACE FUNCTION create_transfer_notification()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO in_process_notifications (transfer, artist, viewed)
  SELECT
    NEW.id,
    c.creator,
    false
  FROM in_process_moments m
  INNER JOIN in_process_collections c ON c.id = m.collection
  WHERE m.id = NEW.moment
  ON CONFLICT (transfer, artist) DO NOTHING;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Fire only when value > 0 (NULL values are excluded by the WHEN clause)
CREATE TRIGGER transfer_notification_trigger
  AFTER INSERT ON in_process_transfers
  FOR EACH ROW
  WHEN (NEW.value >= 0)
  EXECUTE FUNCTION create_transfer_notification();

COMMENT ON FUNCTION create_transfer_notification()
  IS 'Creates a notification for the moment creator when a transfer with value >= 0 is inserted';
COMMENT ON TRIGGER transfer_notification_trigger ON in_process_transfers
  IS 'Fires after INSERT on in_process_transfers when value > 0';
