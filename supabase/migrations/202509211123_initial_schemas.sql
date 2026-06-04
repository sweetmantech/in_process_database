CREATE TABLE in_process_artists (
  address TEXT NOT NULL,
  username TEXT NULL,
  bio TEXT NULL,
  instagram_username TEXT NULL,
  twitter_username TEXT NULL,
  telegram_username TEXT NULL,
  CONSTRAINT in_process_artists_pkey PRIMARY KEY (address)
) tablespace pg_default;

CREATE UNIQUE INDEX if NOT EXISTS idx_in_process_artists_address ON in_process_artists USING btree (address) tablespace pg_default;

CREATE TABLE in_process_tokens (
  id UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  address TEXT NOT NULL DEFAULT ''::TEXT,
  "tokenId" NUMERIC NOT NULL,
  uri TEXT NOT NULL DEFAULT ''::TEXT,
  "defaultAdmin" TEXT NOT NULL DEFAULT ''::TEXT,
  "chainId" NUMERIC NOT NULL,
  "createdAt" TIMESTAMP WITH TIME ZONE NOT NULL,
  hidden BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT in_process_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT in_process_tokens_address_chainid_unique UNIQUE (address, "chainId"),
  CONSTRAINT fk_defaultadmin_artist FOREIGN key ("defaultAdmin") REFERENCES in_process_artists (address) ON UPDATE CASCADE ON DELETE RESTRICT
) tablespace pg_default;

CREATE INDEX if NOT EXISTS idx_in_process_tokens_defaultadmin ON in_process_tokens USING btree ("defaultAdmin") tablespace pg_default;

CREATE TABLE in_process_payments (
  id UUID NOT NULL DEFAULT GEN_RANDOM_UUID(),
  token UUID NOT NULL,
  buyer TEXT NULL,
  amount NUMERIC NULL,
  hash TEXT NULL,
  block NUMERIC NULL,
  CONSTRAINT in_process_payments_pkey PRIMARY KEY (id),
  CONSTRAINT in_process_payments_hash_buyer_token_unique UNIQUE (hash, buyer, token),
  CONSTRAINT in_process_payments_buyer_fkey FOREIGN key (buyer) REFERENCES in_process_artists (address) ON DELETE CASCADE,
  CONSTRAINT in_process_payments_token_fkey FOREIGN key (token) REFERENCES in_process_tokens (id) ON DELETE CASCADE
) tablespace pg_default;
