-- Backfill: insert one canonical smart wallet row per artist
-- Priority: external > privy > farcaster
INSERT INTO in_process_wallets (address, artist, type)
SELECT DISTINCT ON (artist)
  smart_wallet_address,
  artist,
  'smart'::wallet_type
FROM in_process_wallets
WHERE smart_wallet_address IS NOT NULL
ORDER BY artist,
  CASE type
    WHEN 'external'   THEN 1
    WHEN 'privy'      THEN 2
    WHEN 'farcaster'  THEN 3
    ELSE 4
  END
ON CONFLICT DO NOTHING;

-- Enforce 1 smart wallet per artist
CREATE UNIQUE INDEX idx_unique_smart_wallet_per_artist
  ON in_process_wallets (artist)
  WHERE type = 'smart';
