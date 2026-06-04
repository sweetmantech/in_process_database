CREATE OR REPLACE FUNCTION public.in_process_collections_lowercase () returns trigger language plpgsql AS $function$
begin
  new.address := lower(new.address);
  new.creator := lower(new.creator);
  return new;
end;
$function$;

-- Ensure creator artist record exists (satisfies FK constraint)
INSERT INTO
  in_process_artists (address)
VALUES
  ('0x7a6f726121030cadf9923333d5b6f29277024027')
ON CONFLICT (address) DO NOTHING;

-- Insert Zora Media collection
INSERT INTO
  in_process_collections (
    address,
    chain_id,
    name,
    uri,
    creator,
    protocol,
    created_at,
    updated_at
  )
VALUES
  (
    '0xabefbc9fd2f806065b4f3c237d4b59d9a97bcac7',
    1,
    'Zora Media',
    '',
    '0x7a6f726121030cadf9923333d5b6f29277024027',
    'zora_media',
    TO_TIMESTAMP(11565017),
    TO_TIMESTAMP(11565017)
  )
ON CONFLICT (address, chain_id) DO NOTHING;
