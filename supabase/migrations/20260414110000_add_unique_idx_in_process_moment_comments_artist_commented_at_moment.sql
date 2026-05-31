with duplicated_rows as (
  select
    ctid,
    row_number() over (
      partition by artist_address, commented_at, moment
      order by id
    ) as row_num
  from public.in_process_moment_comments
)
delete from public.in_process_moment_comments comments
using duplicated_rows
where comments.ctid = duplicated_rows.ctid
  and duplicated_rows.row_num > 1;

create unique index if not exists in_process_moment_comments_artist_commented_at_moment_unique_idx
  on public.in_process_moment_comments using btree (artist_address, commented_at, moment);
