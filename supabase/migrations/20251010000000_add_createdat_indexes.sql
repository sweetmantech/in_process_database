-- Add index on createdAt for efficient sorting
CREATE INDEX if NOT EXISTS idx_in_process_tokens_createdat ON in_process_tokens USING btree ("createdAt" DESC) tablespace pg_default;

-- Add composite index for artist timeline queries (defaultAdmin + createdAt)
-- This optimizes queries that filter by artist and sort by createdAt
CREATE INDEX if NOT EXISTS idx_in_process_tokens_defaultadmin_createdat ON in_process_tokens USING btree ("defaultAdmin", "createdAt" DESC) tablespace pg_default;

-- Add comment for documentation
COMMENT ON index idx_in_process_tokens_createdat IS 'Improves performance of timeline queries sorted by creation date';

COMMENT ON index idx_in_process_tokens_defaultadmin_createdat IS 'Optimizes artist timeline queries filtered by defaultAdmin and sorted by createdAt';
