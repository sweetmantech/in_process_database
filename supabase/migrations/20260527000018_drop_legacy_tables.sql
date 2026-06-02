-- Drop legacy artist social wallets table (replaced by in_process_wallets)
DROP TABLE IF EXISTS in_process_artist_social_wallets;

-- Drop old artists table (renamed to in_process_artists_old in PR4, now safe to remove)
DROP TABLE IF EXISTS in_process_artists_old;
