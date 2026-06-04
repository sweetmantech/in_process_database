-- For each row in in_process_artist_social_wallets, if both the social_wallet
-- and the linked artist_address have a profile in in_process_artists, clear
-- all non-PK fields on the social_wallet profile.
UPDATE in_process_artists a
SET
  username = NULL,
  bio = NULL,
  instagram_username = NULL,
  twitter_username = NULL,
  telegram_username = NULL,
  farcaster_username = NULL
WHERE
  a.address IN (
    SELECT
      sw.social_wallet
    FROM
      in_process_artist_social_wallets sw
    WHERE
      EXISTS (
        SELECT
          1
        FROM
          in_process_artists b
        WHERE
          b.address = sw.artist_address
      )
      AND EXISTS (
        SELECT
          1
        FROM
          in_process_artists c
        WHERE
          c.address = sw.social_wallet
      )
  );
