UPDATE in_process_wallets
SET smart_wallet_address = NULL
WHERE smart_wallet_address = '';
