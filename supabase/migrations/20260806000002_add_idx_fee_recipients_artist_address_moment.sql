-- Supports get_timeline_stats archived_sums: lookup fee shares by artist wallet,
-- then join paid transfers by moment while reading percent_allocation without a heap fetch.
-- Existing UNIQUE(moment, artist_address) cannot serve artist_address-first lookups.
CREATE INDEX CONCURRENTLY if NOT EXISTS idx_fee_recipients_artist_address_moment ON public.in_process_moment_fee_recipients (artist_address, moment) include (percent_allocation);
