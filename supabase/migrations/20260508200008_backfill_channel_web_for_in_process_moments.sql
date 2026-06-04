UPDATE public.in_process_moments m
SET
  channel = 'web'
FROM
  public.in_process_collections c
WHERE
  m.collection = c.id
  AND c.protocol = 'in_process'
  AND m.channel IS NULL;
