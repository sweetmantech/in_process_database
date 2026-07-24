-- Zora Comments protocol fields for reply threading / replyTo calldata.
-- Nullable: legacy MintComment rows remain NULL (no on-chain CommentIdentifier).
ALTER TABLE public.in_process_moment_comments
ADD COLUMN IF NOT EXISTS comment_id TEXT,
ADD COLUMN IF NOT EXISTS reply_to_id TEXT,
ADD COLUMN IF NOT EXISTS nonce TEXT,
ADD COLUMN IF NOT EXISTS sparks_quantity NUMERIC;
