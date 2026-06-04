INSERT INTO
  in_process_artists_v2 (address, username, bio, x, telegram, instagram)
SELECT
  MIN(address),
  username,
  (
    ARRAY_REMOVE(
      ARRAY_AGG(
        NULLIF(bio, '')
        ORDER BY
          address
      ),
      NULL
    )
  ) [1],
  (
    ARRAY_REMOVE(
      ARRAY_AGG(
        NULLIF(twitter_username, '')
        ORDER BY
          address
      ),
      NULL
    )
  ) [1],
  (
    ARRAY_REMOVE(
      ARRAY_AGG(
        NULLIF(telegram_username, '')
        ORDER BY
          address
      ),
      NULL
    )
  ) [1],
  (
    ARRAY_REMOVE(
      ARRAY_AGG(
        NULLIF(instagram_username, '')
        ORDER BY
          address
      ),
      NULL
    )
  ) [1]
FROM
  in_process_artists
WHERE
  username IS NOT NULL
  AND username != ''
GROUP BY
  username;

INSERT INTO
  in_process_artists_v2 (address, username, bio, x, telegram, instagram)
SELECT
  address,
  NULL,
  NULLIF(bio, ''),
  NULLIF(twitter_username, ''),
  NULLIF(telegram_username, ''),
  NULLIF(instagram_username, '')
FROM
  in_process_artists
WHERE
  username IS NULL
  OR username = '';

INSERT INTO
  in_process_wallets (address, artist, type)
SELECT
  old.address,
  COALESCE(
    (
      SELECT
        v2.id
      FROM
        in_process_artists_v2 v2
      WHERE
        v2.username = old.username
        AND old.username IS NOT NULL
        AND old.username != ''
      LIMIT
        1
    ),
    (
      SELECT
        v2.id
      FROM
        in_process_artists_v2 v2
      WHERE
        v2.address = old.address
      LIMIT
        1
    )
  ),
  NULL
FROM
  in_process_artists old;

UPDATE in_process_wallets w
SET
  smart_wallet_address = old.smart_wallet
FROM
  in_process_artists old
WHERE
  w.address = old.address
  AND old.smart_wallet IS NOT NULL;
