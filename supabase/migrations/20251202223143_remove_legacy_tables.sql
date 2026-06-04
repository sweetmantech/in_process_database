ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_artist_address_fkey";

ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_token_artist_address_unique";

ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_token_fkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
DROP CONSTRAINT "in_process_token_fee_recipients_artist_address_fkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
DROP CONSTRAINT "in_process_token_fee_recipients_token_artist_address_unique";

ALTER TABLE "public"."in_process_token_fee_recipients"
DROP CONSTRAINT "in_process_token_fee_recipients_token_fkey";

ALTER TABLE "public"."in_process_tokens"
DROP CONSTRAINT "fk_defaultadmin_artist";

ALTER TABLE "public"."in_process_tokens"
DROP CONSTRAINT "in_process_tokens_address_chainid_unique";

ALTER TABLE "public"."in_process_token_admins"
DROP CONSTRAINT "in_process_token_admins_pkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
DROP CONSTRAINT "in_process_token_fee_recipients_pkey";

ALTER TABLE "public"."in_process_tokens"
DROP CONSTRAINT "in_process_tokens_pkey";

DROP INDEX if EXISTS "public"."idx_in_process_tokens_createdat";

DROP INDEX if EXISTS "public"."idx_in_process_tokens_defaultadmin";

DROP INDEX if EXISTS "public"."idx_in_process_tokens_defaultadmin_createdat";

DROP INDEX if EXISTS "public"."in_process_token_admins_pkey";

DROP INDEX if EXISTS "public"."in_process_token_admins_token_artist_address_unique";

DROP INDEX if EXISTS "public"."in_process_token_fee_recipients_pkey";

DROP INDEX if EXISTS "public"."in_process_token_fee_recipients_token_artist_address_unique";

DROP INDEX if EXISTS "public"."in_process_tokens_address_chainid_unique";

DROP INDEX if EXISTS "public"."in_process_tokens_pkey";

DROP TABLE "public"."in_process_token_admins";

DROP TABLE "public"."in_process_token_fee_recipients";

DROP TABLE "public"."in_process_tokens";
