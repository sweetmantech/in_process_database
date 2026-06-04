UPDATE in_process_collections
SET
  created_at = TO_TIMESTAMP(1609459166),
  updated_at = TO_TIMESTAMP(1609459166)
WHERE
  address = '0xabefbc9fd2f806065b4f3c237d4b59d9a97bcac7'
  AND chain_id = 1;
