-- Drop the get_in_process_payments RPC (both overloads), all indexes,
-- and the in_process_payments table itself.

-- ── RPC functions ────────────────────────────────────────────────────────
-- 5-param overload (original, no mime)
DROP FUNCTION IF EXISTS public.get_in_process_payments(integer, integer, text[], text[], numeric);
-- 6-param overload (with mime filter)
DROP FUNCTION IF EXISTS public.get_in_process_payments(integer, integer, text[], text[], numeric, text);

-- ── Indexes on in_process_payments ───────────────────────────────────────
DROP INDEX IF EXISTS public.idx_payments_transferred_at_desc;
DROP INDEX IF EXISTS public.idx_payments_moment;
DROP INDEX IF EXISTS public.idx_payments_buyer;

-- ── Unique constraints (converted to unique indexes by Postgres) ──────────
ALTER TABLE public.in_process_payments
  DROP CONSTRAINT IF EXISTS in_process_payments_buyer_transaction_hash_moment_unique;
ALTER TABLE public.in_process_payments
  DROP CONSTRAINT IF EXISTS in_process_payments_hash_buyer_token_unique;

-- ── Table ─────────────────────────────────────────────────────────────────
-- CASCADE drops any remaining FK references (e.g. in_process_notifications.payment
-- if it were still present — already removed in 20260416100000).
DROP TABLE IF EXISTS public.in_process_payments CASCADE;
