-- Migrate in_process_api_keys from artist_address (text) to artist_id (uuid).
-- Keys must follow the artist entity (UUID) so that adding or removing wallets
-- does not require shuffling keys between addresses.

-- 1. Add the new artist_id column referencing the artist entity.
ALTER TABLE in_process_api_keys
  ADD COLUMN IF NOT EXISTS artist_id uuid
    REFERENCES in_process_artists(id) ON DELETE CASCADE;

-- 2. Backfill: artist_address -> in_process_wallets -> artist UUID.
UPDATE in_process_api_keys k
SET artist_id = w.artist
FROM in_process_wallets w
WHERE w.address = k.artist_address
  AND w.artist IS NOT NULL
  AND k.artist_id IS NULL;

-- 3. Deduplicate: when multiple keys collapse onto the same artist_id, keep
--    the one whose artist_address corresponds to an external wallet (the
--    user-facing wallet), falling back to the lowest id deterministically.
DELETE FROM in_process_api_keys k
WHERE artist_id IS NOT NULL
  AND id NOT IN (
    SELECT DISTINCT ON (k2.artist_id) k2.id
    FROM in_process_api_keys k2
    LEFT JOIN in_process_wallets w
      ON w.address = k2.artist_address
     AND w.type = 'external'
    WHERE k2.artist_id IS NOT NULL
    ORDER BY k2.artist_id,
             (w.address IS NOT NULL) DESC,
             k2.id ASC
  )
  AND artist_id IN (
    SELECT artist_id
    FROM in_process_api_keys
    WHERE artist_id IS NOT NULL
    GROUP BY artist_id
    HAVING COUNT(*) > 1
  );

-- 4. Index artist_id for lookup-by-artist (getApiKeys / getArtistApiKeysHandler).
CREATE INDEX IF NOT EXISTS idx_in_process_api_keys_artist_id
  ON in_process_api_keys (artist_id);
