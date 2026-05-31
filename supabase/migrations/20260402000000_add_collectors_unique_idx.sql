-- Remove duplicate rows, keeping the one with the lowest id per (collector, moment, transaction_hash)
DELETE FROM public.in_process_collectors
WHERE id IN (
  SELECT id
  FROM (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY collector, moment, transaction_hash
        ORDER BY id
      ) AS rn
    FROM public.in_process_collectors
  ) ranked
  WHERE rn > 1
);

CREATE UNIQUE INDEX in_process_collectors_collector_moment_transaction_idx
  ON public.in_process_collectors USING btree (collector, moment, transaction_hash);
