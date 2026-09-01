-- PR 6: Link IN PUBLIC handoff wallets to Yuri (bigvibesssss).
-- Only 0xf324… is external (creator EOA). 0xe537… / 0x4f9bf… are linked identity
-- wallets only — not In Process smart (Coinbase) or privy embedded wallets.
INSERT INTO
  in_process_wallets (address, artist, type)
VALUES
  (
    '0xf32484112e0b6c994f5db084d5c15f2a1d6a4228',
    (
      SELECT
        id
      FROM
        in_process_artists
      WHERE
        username = 'bigvibesssss'
    ),
    'external'::wallet_type
  )
ON CONFLICT (address) DO UPDATE
SET
  artist = excluded.artist,
  type = excluded.type;

INSERT INTO
  in_process_wallets (address, artist, type)
VALUES
  (
    '0xe5379c3844eeb8ecb326804b3d717133841fbc37',
    (
      SELECT
        id
      FROM
        in_process_artists
      WHERE
        username = 'bigvibesssss'
    ),
    NULL
  )
ON CONFLICT (address) DO UPDATE
SET
  artist = excluded.artist,
  type = NULL;

INSERT INTO
  in_process_wallets (address, artist, type)
VALUES
  (
    '0x4f9bf932e13a4d6e7395628df78523c6b3eac069',
    (
      SELECT
        id
      FROM
        in_process_artists
      WHERE
        username = 'bigvibesssss'
    ),
    NULL
  )
ON CONFLICT (address) DO UPDATE
SET
  artist = excluded.artist,
  type = NULL;
