WITH normalized AS (
  SELECT id, handle, lower(trim(username)) AS candidate
  FROM in_process_artists
  WHERE username IS NOT NULL AND trim(username) <> ''
),
eligible AS (
  SELECT id, candidate
  FROM (
    SELECT *, count(*) OVER (PARTITION BY candidate) AS duplicates
    FROM normalized
  ) ranked
  WHERE handle IS NULL
    AND duplicates = 1
    AND candidate ~ '^[a-z0-9][a-z0-9._-]{1,28}[a-z0-9]$'
    AND candidate !~ '^0x'
    AND candidate !~ '\.[a-z0-9]{2,5}$'
    AND candidate NOT IN (
      'admin', 'analytics', 'api', 'arweave', 'collect', 'collection', 'create',
      'faq', 'fonts', 'icons', 'images', 'inprocess', 'inpublic', 'manage',
      'manifesto', 'notifications', 'nouns', 'sms', 'topup'
    )
    AND NOT EXISTS (
      SELECT 1 FROM in_process_artists taken WHERE taken.handle = candidate
    )
)
UPDATE in_process_artists artists
SET handle = eligible.candidate
FROM eligible
WHERE artists.id = eligible.id
  AND artists.handle IS NULL;
