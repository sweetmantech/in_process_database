WITH
  duplicated_rows AS (
    SELECT
      ctid,
      ROW_NUMBER() OVER (
        PARTITION BY
          artist_address,
          commented_at,
          moment
        ORDER BY
          id
      ) AS row_num
    FROM
      public.in_process_moment_comments
  )
DELETE FROM public.in_process_moment_comments comments USING duplicated_rows
WHERE
  comments.ctid = duplicated_rows.ctid
  AND duplicated_rows.row_num > 1;

CREATE UNIQUE INDEX if NOT EXISTS in_process_moment_comments_artist_commented_at_moment_unique_idx ON public.in_process_moment_comments USING btree (artist_address, commented_at, moment);
