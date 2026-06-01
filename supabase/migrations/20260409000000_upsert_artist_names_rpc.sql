CREATE OR REPLACE FUNCTION upsert_artist_names(
  artists jsonb
)
RETURNS void
LANGUAGE plpgsql
AS $$
DECLARE
  artist jsonb;
BEGIN
  FOR artist IN SELECT * FROM jsonb_array_elements(artists)
  LOOP
    IF artist->>'address' IS NOT NULL THEN
      INSERT INTO in_process_artists (address, username)
      VALUES (
        artist->>'address',
        artist->>'username'
      )
      ON CONFLICT (address) DO UPDATE
        SET username = EXCLUDED.username
        WHERE in_process_artists.username IS NULL;
    END IF;
  END LOOP;
END;
$$;
