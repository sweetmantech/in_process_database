CREATE OR REPLACE FUNCTION public.in_process_collections_lowercase()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
begin
  new.address := lower(new.address);
  new.creator := lower(new.creator);
  return new;
end;
$function$
;
-- Ensure creator artist record exists (satisfies FK constraint)
insert into in_process_artists (address)
values ('0x7a6f726121030cadf9923333d5b6f29277024027')
on conflict (address) do nothing;

-- Insert Zora Media collection
insert into in_process_collections (address, chain_id, name, uri, creator, protocol, created_at, updated_at)
values (
  '0xabefbc9fd2f806065b4f3c237d4b59d9a97bcac7',
  1,
  'Zora Media',
  '',
  '0x7a6f726121030cadf9923333d5b6f29277024027',
  'zora_media',
  to_timestamp(11565017),
  to_timestamp(11565017)
)
on conflict (address, chain_id) do nothing;
