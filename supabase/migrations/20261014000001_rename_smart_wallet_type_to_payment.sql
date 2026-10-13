ALTER TYPE wallet_type
RENAME value 'smart' TO 'payment';

ALTER INDEX idx_unique_smart_wallet_per_artist
RENAME TO idx_unique_payment_wallet_per_artist;
