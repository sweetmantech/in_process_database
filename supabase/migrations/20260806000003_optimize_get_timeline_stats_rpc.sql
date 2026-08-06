CREATE OR REPLACE FUNCTION public.get_timeline_stats (p_artist TEXT) returns TABLE (
  created_count BIGINT,
  eth_archived TEXT,
  usdc_archived TEXT
) language sql stable AS $$
  WITH artist_addrs AS MATERIALIZED (
    SELECT w.artist AS artist_id, w.address
    FROM public.in_process_wallets w
    WHERE w.artist = (
      SELECT w2.artist
      FROM public.in_process_wallets w2
      WHERE w2.address = LOWER(p_artist)
      LIMIT 1
    )
  ),
  timeline_moments AS MATERIALIZED (
    -- default: moments in collections this artist created
    SELECT DISTINCT m.id AS moment_id
    FROM artist_addrs aa
    INNER JOIN public.in_process_collections c
      ON c.creator = aa.address
     AND c.protocol = 'in_process'
     AND c.chain_id = 8453
    INNER JOIN public.in_process_moments m ON m.collection = c.id

    UNION

    -- mutual: exact token admin, excluding collections this artist created
    SELECT DISTINCT m.id AS moment_id
    FROM artist_addrs aa
    INNER JOIN public.in_process_admins adm
      ON adm.artist_address = aa.address
     AND adm.token_id <> 0
    INNER JOIN public.in_process_moments m
      ON m.collection = adm.collection
     AND m.token_id = adm.token_id
    INNER JOIN public.in_process_collections c
      ON c.id = m.collection
     AND c.protocol = 'in_process'
     AND c.chain_id = 8453
    WHERE NOT EXISTS (
      SELECT 1
      FROM artist_addrs aa2
      WHERE aa2.address = c.creator
    )

    UNION

    -- mutual: collection-level admin (token_id = 0), excluding creator collections
    SELECT DISTINCT m.id AS moment_id
    FROM artist_addrs aa
    INNER JOIN public.in_process_admins adm
      ON adm.artist_address = aa.address
     AND adm.token_id = 0
    INNER JOIN public.in_process_collections c
      ON c.id = adm.collection
     AND c.protocol = 'in_process'
     AND c.chain_id = 8453
    INNER JOIN public.in_process_moments m ON m.collection = c.id
    WHERE NOT EXISTS (
      SELECT 1
      FROM artist_addrs aa2
      WHERE aa2.address = c.creator
    )
  ),
  eligible_fee_shares AS MATERIALIZED (
    SELECT
      aa.artist_id,
      fr.moment AS moment_id,
      fr.percent_allocation
    FROM artist_addrs aa
    INNER JOIN public.in_process_moment_fee_recipients fr
      ON fr.artist_address = aa.address
    INNER JOIN public.in_process_moments m ON m.id = fr.moment
    INNER JOIN public.in_process_collections c
      ON c.id = m.collection
     AND c.protocol = 'in_process'
     AND c.chain_id = 8453
  ),
  archived_sums AS (
    SELECT
      efs.artist_id,
      COALESCE(
        SUM(
          (t.value::NUMERIC * efs.percent_allocation) / 100
        ) FILTER (
          WHERE t.currency = '0x0000000000000000000000000000000000000000'
        ),
        0
      ) AS eth_archived,
      COALESCE(
        SUM(
          (t.value::NUMERIC * efs.percent_allocation) / 100
        ) FILTER (
          WHERE t.currency = '0x833589fcd6edb6e08f4c7c32d4f71b54bda02913'
        ),
        0
      ) AS usdc_archived
    FROM eligible_fee_shares efs
    INNER JOIN public.in_process_transfers t
      ON t.moment = efs.moment_id
     AND t.value IS NOT NULL
    GROUP BY efs.artist_id
  )
  SELECT
    (SELECT COUNT(*)::BIGINT FROM timeline_moments),
    TRIM(
      TRAILING '.' FROM to_char(
        COALESCE((SELECT eth_archived FROM archived_sums LIMIT 1), 0),
        'FM999999999999990.999999999999999999'
      )
    ),
    TRIM(
      TRAILING '.' FROM to_char(
        COALESCE((SELECT usdc_archived FROM archived_sums LIMIT 1), 0),
        'FM999999999999990.999999'
      )
    )
  WHERE EXISTS (SELECT 1 FROM artist_addrs);
$$;
