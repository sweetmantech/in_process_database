-- Remove smart_wallet_address from lowercase trigger
CREATE OR REPLACE FUNCTION trg_wallets_lowercase () returns trigger language plpgsql AS $$
BEGIN
  NEW.address := lower(NEW.address);
  RETURN NEW;
END;
$$;

-- Drop the column — smart wallets are now their own rows (type='smart')
ALTER TABLE in_process_wallets
DROP COLUMN smart_wallet_address;
