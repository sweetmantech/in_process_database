-- Drop the get_in_process_payments RPC (both overloads), all indexes,
-- and the in_process_payments table itself.
-- ── RPC functions ────────────────────────────────────────────────────────
-- 5-param overload (original, no mime)
DROP FUNCTION if EXISTS public.get_in_process_payments (INTEGER, INTEGER, TEXT[], TEXT[], NUMERIC);

-- 6-param overload (with mime filter)
DROP FUNCTION if EXISTS public.get_in_process_payments (INTEGER, INTEGER, TEXT[], TEXT[], NUMERIC, TEXT);

-- ── Indexes on in_process_payments ───────────────────────────────────────
DROP INDEX if EXISTS public.idx_payments_transferred_at_desc;

DROP INDEX if EXISTS public.idx_payments_moment;

DROP INDEX if EXISTS public.idx_payments_buyer;

-- ── Unique constraints (converted to unique indexes by Postgres) ──────────
ALTER TABLE public.in_process_payments
DROP CONSTRAINT if EXISTS in_process_payments_buyer_transaction_hash_moment_unique;

ALTER TABLE public.in_process_payments
DROP CONSTRAINT if EXISTS in_process_payments_hash_buyer_token_unique;

-- ── Table ─────────────────────────────────────────────────────────────────
-- CASCADE drops any remaining FK references (e.g. in_process_notifications.payment
-- if it were still present — already removed in 20260416100000).
DROP TABLE IF EXISTS public.in_process_payments cascade;
