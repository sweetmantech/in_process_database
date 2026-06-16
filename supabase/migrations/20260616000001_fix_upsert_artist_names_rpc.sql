-- Fix upsert_artist_names RPC: in_process_artists.address was dropped in
-- 20260528000001, so replace all direct address lookups on in_process_artists
-- with wallet-based lookups through in_process_wallets.
CREATE OR REPLACE FUNCTION upsert_artist_names (artists JSONB) returns void language plpgsql AS $$
DECLARE
  artist     jsonb;
  v_artist_id uuid;
BEGIN
  FOR artist IN SELECT * FROM jsonb_array_elements(artists) LOOP
    CONTINUE WHEN artist->>'address' IS NULL;

    v_artist_id := NULL;

    -- 1. Look up existing artist via wallet address
    SELECT w.artist INTO v_artist_id FROM in_process_wallets w
    WHERE w.address = lower(artist->>'address')
      AND w.artist IS NOT NULL;

    -- 2. Fall back to lookup by username
    IF v_artist_id IS NULL AND artist->>'username' IS NOT NULL THEN
      SELECT id INTO v_artist_id FROM in_process_artists
      WHERE username = artist->>'username';
    END IF;

    IF v_artist_id IS NULL THEN
      -- 3. Create new artist row (no address column anymore)
      INSERT INTO in_process_artists (username)
      VALUES (artist->>'username')
      RETURNING id INTO v_artist_id;
    ELSE
      -- 4. Fill in username if the artist record doesn't have one yet
      UPDATE in_process_artists
      SET username = artist->>'username'
      WHERE id = v_artist_id
        AND username IS NULL
        AND artist->>'username' IS NOT NULL;
    END IF;

    -- 5. Ensure wallet exists and is linked to the artist
    INSERT INTO in_process_wallets (address, artist, type)
    VALUES (lower(artist->>'address'), v_artist_id, NULL)
    ON CONFLICT (address) DO UPDATE
      SET artist = COALESCE(in_process_wallets.artist, EXCLUDED.artist);
  END LOOP;
END;
$$;
