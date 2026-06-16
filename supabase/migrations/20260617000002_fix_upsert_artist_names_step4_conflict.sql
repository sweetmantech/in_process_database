-- Fix: step 4 UPDATE raises unique_violation when another artist already owns
-- the username. Re-link the wallet to that existing artist and delete the
-- now-orphaned artist row if it has no remaining wallets.
CREATE OR REPLACE FUNCTION upsert_artist_names (artists JSONB) returns void language plpgsql AS $$
DECLARE
  r                    jsonb;
  v_address            text;
  v_username           text;
  v_artist_id          uuid;
  v_existing_artist_id uuid;
  v_old_artist_id      uuid;
BEGIN
  FOR r IN SELECT * FROM jsonb_array_elements(artists) LOOP
    v_address  := lower(r->>'address');
    v_username := r->>'username';

    CONTINUE WHEN coalesce(trim(v_address), '') = '';

    v_artist_id := NULL;

    -- 1. Look up existing artist via wallet address
    SELECT w.artist INTO v_artist_id FROM in_process_wallets w
    WHERE w.address = v_address AND w.artist IS NOT NULL;

    -- 2. Fall back to lookup by username
    IF v_artist_id IS NULL AND v_username IS NOT NULL THEN
      SELECT id INTO v_artist_id FROM in_process_artists
      WHERE lower(username) = lower(v_username);
    END IF;

    IF v_artist_id IS NULL THEN
      -- 3. Create new artist row; on conflict link to the existing artist
      INSERT INTO in_process_artists (username)
      VALUES (v_username)
      ON CONFLICT (username) DO UPDATE SET username = EXCLUDED.username
      RETURNING id INTO v_artist_id;
    ELSE
      -- 4. Fill in username if the artist record doesn't have one yet.
      BEGIN
        UPDATE in_process_artists
        SET username = v_username
        WHERE id = v_artist_id AND username IS NULL AND v_username IS NOT NULL;
      EXCEPTION WHEN unique_violation THEN
        -- Another artist already owns this username. Re-link the wallet to
        -- that artist and delete the old artist if it becomes an orphan.
        v_old_artist_id := v_artist_id;

        SELECT id INTO v_existing_artist_id FROM in_process_artists
        WHERE lower(username) = lower(v_username);

        UPDATE in_process_wallets SET artist = v_existing_artist_id
        WHERE address = v_address;

        v_artist_id := v_existing_artist_id;

        DELETE FROM in_process_artists
        WHERE id = v_old_artist_id
          AND NOT EXISTS (
            SELECT 1 FROM in_process_wallets WHERE artist = v_old_artist_id
          );
      END;
    END IF;

    -- 5. Ensure wallet exists and is linked to the artist
    INSERT INTO in_process_wallets (address, artist, type)
    VALUES (v_address, v_artist_id, NULL)
    ON CONFLICT (address) DO UPDATE
      SET artist = COALESCE(in_process_wallets.artist, EXCLUDED.artist);
  END LOOP;
END;
$$;
