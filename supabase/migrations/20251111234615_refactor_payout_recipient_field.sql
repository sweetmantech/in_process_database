ALTER TABLE "public"."in_process_tokens"
DROP COLUMN "payoutRecipientNotDefaultAdmin";

ALTER TABLE "public"."in_process_tokens"
ADD COLUMN "payoutRecipient" TEXT;
