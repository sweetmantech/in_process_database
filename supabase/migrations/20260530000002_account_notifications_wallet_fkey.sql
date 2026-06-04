-- Add missing FK constraint on account_notifications.wallet.
-- in_process_notifications got this constraint in the same migration
-- (20260530000001) but account_notifications was left without it.
ALTER TABLE public.account_notifications
ADD CONSTRAINT account_notifications_wallet_fkey FOREIGN key (wallet) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE;
