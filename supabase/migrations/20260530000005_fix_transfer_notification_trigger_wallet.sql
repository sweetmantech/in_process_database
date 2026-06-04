-- The create_transfer_notification trigger still referenced the old `artist`
-- column which was dropped in 20260528000003 (renamed artist → artist_id)
-- and then again in 20260530000001 (renamed artist_id → wallet).
-- The UNIQUE (transfer, artist) constraint was implicitly dropped with the
-- column; recreate it as UNIQUE (transfer, wallet) and update the trigger.
-- Add unique constraint so ON CONFLICT works
ALTER TABLE public.in_process_notifications
ADD CONSTRAINT unique_transfer_wallet UNIQUE (transfer, wallet);

-- Drop existing trigger first (required before dropping the function)
DROP TRIGGER if EXISTS transfer_notification_trigger ON public.in_process_transfers;

DROP FUNCTION if EXISTS create_transfer_notification ();

-- Recreate trigger function using the current column name
CREATE OR REPLACE FUNCTION create_transfer_notification () returns trigger AS $$
BEGIN
  INSERT INTO in_process_notifications (transfer, wallet, viewed)
  SELECT
    NEW.id,
    c.creator,
    false
  FROM in_process_moments m
  INNER JOIN in_process_collections c ON c.id = m.collection
  WHERE m.id = NEW.moment
  ON CONFLICT (transfer, wallet) DO NOTHING;

  RETURN NEW;
END;
$$ language plpgsql;

CREATE TRIGGER transfer_notification_trigger
AFTER INSERT ON public.in_process_transfers FOR EACH ROW WHEN (new.value >= 0)
EXECUTE FUNCTION create_transfer_notification ();
