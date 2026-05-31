CREATE OR REPLACE FUNCTION upsert_artist_names(artists jsonb)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  artist     jsonb;
  v_artist_id uuid;
BEGIN
  FOR artist IN SELECT * FROM jsonb_array_elements(artists) LOOP
    CONTINUE WHEN artist->>'address' IS NULL;

    v_artist_id := NULL;

    IF artist->>'username' IS NOT NULL THEN
      SELECT id INTO v_artist_id FROM in_process_artists
      WHERE username = artist->>'username';
    END IF;

    IF v_artist_id IS NULL THEN
      SELECT id INTO v_artist_id FROM in_process_artists
      WHERE address = lower(artist->>'address');
    END IF;

    IF v_artist_id IS NULL THEN
      INSERT INTO in_process_artists (address, username)
      VALUES (lower(artist->>'address'), artist->>'username')
      ON CONFLICT DO NOTHING
      RETURNING id INTO v_artist_id;

      IF v_artist_id IS NULL THEN
        SELECT id INTO v_artist_id FROM in_process_artists
        WHERE address = lower(artist->>'address');
      END IF;
    ELSE
      UPDATE in_process_artists
      SET username = artist->>'username'
      WHERE id = v_artist_id
        AND username IS NULL
        AND artist->>'username' IS NOT NULL;
    END IF;

    INSERT INTO in_process_wallets (address, artist, type)
    VALUES (lower(artist->>'address'), v_artist_id, NULL)
    ON CONFLICT (address) DO NOTHING;
  END LOOP;
END;
$$;
