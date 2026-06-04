-- Re-point FKs that were broken by the table rename in migration 000007.
-- After renaming in_process_artists → in_process_artists_old, these FKs
-- were left pointing at in_process_artists_old instead of the new in_process_artists.
ALTER TABLE in_process_artist_social_wallets
DROP CONSTRAINT if EXISTS in_process_artist_social_wallets_artist_address_fkey,
ADD CONSTRAINT in_process_artist_social_wallets_artist_address_fkey FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON DELETE CASCADE NOT valid;

ALTER TABLE in_process_moment_comments
DROP CONSTRAINT if EXISTS in_process_moment_comments_artist_address_fkey,
ADD CONSTRAINT in_process_moment_comments_artist_address_fkey FOREIGN key (artist_address) REFERENCES in_process_artists (address) ON DELETE CASCADE NOT valid;

ALTER TABLE in_process_transfers
DROP CONSTRAINT if EXISTS in_process_transfers_recipient_fkey,
ADD CONSTRAINT in_process_transfers_recipient_fkey FOREIGN key (recipient) REFERENCES in_process_artists (address) ON DELETE SET NULL NOT valid;
