-- Normalize telegram handles to lowercase so eq(telegram, lower(input)) can use a btree index.
UPDATE public.in_process_artists
SET
  telegram = LOWER(telegram)
WHERE
  telegram IS NOT NULL
  AND telegram <> ''
  AND telegram <> LOWER(telegram);
