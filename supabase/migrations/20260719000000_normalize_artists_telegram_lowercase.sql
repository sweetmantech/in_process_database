-- The Telegram connect flow previously stored in_process_artists.telegram
-- with whatever casing Telegram returned, while every lookup compares
-- against lower(telegram) (see selectArtists.ts). Any artist whose Telegram
-- username contains uppercase letters never matched again after the first
-- connect, so the bot treated them as unconnected on every subsequent
-- message. The app now writes telegram already lowercased; this backfills
-- existing rows to match.
UPDATE in_process_artists
SET
  telegram = LOWER(telegram)
WHERE
  telegram IS NOT NULL
  AND telegram <> LOWER(telegram);
