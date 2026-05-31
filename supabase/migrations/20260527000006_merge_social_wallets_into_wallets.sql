DO $$
DECLARE
  sw     RECORD;
  a_uuid uuid;
  b_uuid uuid;
  b_row  in_process_artists_v2%ROWTYPE;
BEGIN
  FOR sw IN SELECT social_wallet, artist_address FROM in_process_artist_social_wallets LOOP
    SELECT artist INTO a_uuid FROM in_process_wallets WHERE address = sw.social_wallet;
    SELECT artist INTO b_uuid FROM in_process_wallets WHERE address = sw.artist_address;

    CONTINUE WHEN a_uuid IS NULL OR b_uuid IS NULL OR a_uuid = b_uuid;

    SELECT * INTO b_row FROM in_process_artists_v2 WHERE id = b_uuid;

    UPDATE in_process_wallets SET artist = a_uuid WHERE artist = b_uuid;

    DELETE FROM in_process_artists_v2 WHERE id = b_uuid;

    UPDATE in_process_artists_v2
    SET
      username  = COALESCE(username,  b_row.username),
      bio       = COALESCE(bio,       b_row.bio),
      x         = COALESCE(x,         b_row.x),
      telegram  = COALESCE(telegram,  b_row.telegram),
      instagram = COALESCE(instagram, b_row.instagram)
    WHERE id = a_uuid;

    UPDATE in_process_wallets SET type = 'privy'    WHERE address = sw.social_wallet;
    UPDATE in_process_wallets SET type = 'external' WHERE address = sw.artist_address;
  END LOOP;
END;
$$;
