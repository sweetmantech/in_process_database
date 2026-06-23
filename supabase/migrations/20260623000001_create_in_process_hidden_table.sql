-- in_process_hidden replaces the hidden=true pattern in in_process_admins.
-- Record presence means hidden; absence means visible. No hidden=false rows needed.
-- token_id=0 (collection-level wildcard) records are skipped — no moment to map to.
CREATE TABLE "public"."in_process_hidden" (
  "id" UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  "moment" UUID NOT NULL,
  "wallet" TEXT NOT NULL,
  "hidden_at" TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE "public"."in_process_hidden" enable ROW level security;

CREATE UNIQUE INDEX in_process_hidden_pkey ON public.in_process_hidden USING btree (id);

ALTER TABLE "public"."in_process_hidden"
ADD CONSTRAINT "in_process_hidden_pkey" PRIMARY KEY USING index "in_process_hidden_pkey";

ALTER TABLE "public"."in_process_hidden"
ADD CONSTRAINT "in_process_hidden_moment_fkey" FOREIGN key (moment) REFERENCES public.in_process_moments (id) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_hidden" validate CONSTRAINT "in_process_hidden_moment_fkey";

ALTER TABLE "public"."in_process_hidden"
ADD CONSTRAINT "in_process_hidden_wallet_fkey" FOREIGN key (wallet) REFERENCES public.in_process_wallets (address) ON UPDATE CASCADE ON DELETE CASCADE NOT valid;

ALTER TABLE "public"."in_process_hidden" validate CONSTRAINT "in_process_hidden_wallet_fkey";

CREATE UNIQUE INDEX in_process_hidden_moment_wallet_unique ON public.in_process_hidden USING btree (moment, wallet);

ALTER TABLE "public"."in_process_hidden"
ADD CONSTRAINT "in_process_hidden_moment_wallet_unique" UNIQUE USING index "in_process_hidden_moment_wallet_unique";

-- Migrate token-specific hidden records. token_id=0 records are skipped (no moment to map to).
INSERT INTO
  public.in_process_hidden (moment, wallet, hidden_at)
SELECT
  m.id,
  adm.artist_address,
  adm.granted_at
FROM
  public.in_process_admins adm
  JOIN public.in_process_moments m ON m.collection = adm.collection
  AND m.token_id = adm.token_id
  JOIN public.in_process_wallets w ON w.address = adm.artist_address
WHERE
  adm.hidden = TRUE
  AND adm.token_id != 0
ON CONFLICT (moment, wallet) DO NOTHING;
