DELETE FROM "public"."in_process_payments";

ALTER TABLE "public"."in_process_payments"
DROP CONSTRAINT "in_process_payments_token_fkey";

ALTER TABLE "public"."in_process_payments"
DROP CONSTRAINT if EXISTS "in_process_payments_hash_buyer_token_unique";

ALTER TABLE "public"."in_process_payments"
DROP COLUMN "block";

ALTER TABLE "public"."in_process_payments"
DROP COLUMN "hash";

ALTER TABLE "public"."in_process_payments"
DROP COLUMN "token";

ALTER TABLE "public"."in_process_payments"
ADD COLUMN "moment" UUID NOT NULL;

ALTER TABLE "public"."in_process_payments"
ADD COLUMN "transaction_hash" TEXT NOT NULL;

ALTER TABLE "public"."in_process_payments"
ADD COLUMN "transferred_at" TIMESTAMP WITH TIME ZONE NOT NULL;

ALTER TABLE "public"."in_process_payments"
ALTER COLUMN "amount"
SET NOT NULL;

ALTER TABLE "public"."in_process_payments"
ALTER COLUMN "buyer"
SET NOT NULL;

ALTER TABLE "public"."in_process_payments" enable ROW level security;

ALTER TABLE "public"."in_process_payments"
ADD CONSTRAINT "in_process_payments_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_payments" validate CONSTRAINT "in_process_payments_moment_fkey";

ALTER TABLE "public"."in_process_payments"
ADD CONSTRAINT "in_process_payments_buyer_transaction_hash_moment_unique" UNIQUE (buyer, transaction_hash, moment);
