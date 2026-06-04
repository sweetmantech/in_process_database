CREATE TABLE "public"."in_process_token_fee_recipients" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "token" UUID NOT NULL,
  "artist_address" TEXT NOT NULL,
  "percentAllocation" NUMERIC,
  "created_at" TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_token_fee_recipients" enable ROW level security;

CREATE UNIQUE INDEX in_process_token_fee_recipients_pkey ON public.in_process_token_fee_recipients USING btree (id);

ALTER TABLE "public"."in_process_token_fee_recipients"
ADD CONSTRAINT "in_process_token_fee_recipients_pkey" PRIMARY KEY USING index "in_process_token_fee_recipients_pkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
ADD CONSTRAINT "in_process_token_fee_recipients_artist_address_fkey" FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_token_fee_recipients" validate CONSTRAINT "in_process_token_fee_recipients_artist_address_fkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
ADD CONSTRAINT "in_process_token_fee_recipients_token_fkey" FOREIGN key (token) REFERENCES in_process_tokens (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_token_fee_recipients" validate CONSTRAINT "in_process_token_fee_recipients_token_fkey";

ALTER TABLE "public"."in_process_token_fee_recipients"
ADD CONSTRAINT "in_process_token_fee_recipients_token_artist_address_unique" UNIQUE (token, artist_address);
