DROP FUNCTION if EXISTS public.get_airdrop_transfers (TEXT, TEXT, NUMERIC, TEXT, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION public.get_airdrop_transfers (
  p_artist TEXT DEFAULT NULL,
  p_collector TEXT DEFAULT NULL,
  p_chain_id NUMERIC DEFAULT NULL,
  p_content_type TEXT DEFAULT NULL,
  p_limit INTEGER DEFAULT 20,
  p_offset INTEGER DEFAULT 0
) returns TABLE (transfers JSONB, total_count BIGINT) language sql stable AS $function$
  WITH filtered_collections AS (
    SELECT c.id
    FROM public.in_process_collections c
    WHERE c.protocol = 'in_process'
      AND (p_chain_id IS NULL OR c.chain_id = p_chain_id)
      AND (p_artist IS NULL OR c.creator = lower(p_artist))
      AND (p_collector IS NULL OR c.creator <> lower(p_collector))
  ),
  filtered_moments AS (
    SELECT m.id
    FROM public.in_process_moments m
    JOIN filtered_collections fc ON fc.id = m.collection
  ),
  filtered_transfers AS (
    SELECT
      t.id,
      t.moment,
      t.recipient,
      t.quantity,
      t.currency,
      t.value,
      t.transaction_hash,
      t.transferred_at
    FROM public.in_process_transfers t
    JOIN filtered_moments fm ON fm.id = t.moment
    WHERE t.value IS NULL
      AND (p_artist IS NULL OR t.recipient <> lower(p_artist))
      AND (p_collector IS NULL OR t.recipient = lower(p_collector))
  ),
  filtered_with_joins AS (
    SELECT
      ft.id,
      ft.transferred_at,
      jsonb_build_object(
        'id', ft.id,
        'quantity', ft.quantity,
        'currency', ft.currency,
        'value', ft.value,
        'transaction_hash', ft.transaction_hash,
        'transferred_at', ft.transferred_at,
        'collector', jsonb_build_object(
          'address', collector.address,
          'username', collector.username
        ),
        'moment', jsonb_build_object(
          'token_id', m.token_id,
          'collection', jsonb_build_object(
            'address', c.address,
            'chain_id', c.chain_id,
            'protocol', c.protocol,
            'artist', jsonb_build_object(
              'address', creator.address,
              'username', creator.username
            )
          ),
          'metadata', jsonb_build_object(
            'name', md.name,
            'description', md.description,
            'external_url', md.external_url,
            'image', md.image,
            'animation_url', md.animation_url,
            'content', md.content
          )
        )
      ) AS transfer
    FROM filtered_transfers ft
    JOIN public.in_process_moments m ON m.id = ft.moment
    JOIN public.in_process_collections c ON c.id = m.collection
    JOIN public.in_process_artists creator ON creator.address = c.creator
    JOIN public.in_process_artists collector ON collector.address = ft.recipient
    LEFT JOIN public.in_process_metadata md ON md.moment = m.id
    WHERE (
      p_content_type IS NULL
      OR lower(md.content->>'mime') LIKE '%' || lower(p_content_type) || '%'
    )
  ),
  counted AS (
    SELECT count(*)::bigint AS total_count
    FROM filtered_with_joins
  ),
  paged AS (
    SELECT transfer, transferred_at, id
    FROM filtered_with_joins
    ORDER BY transferred_at DESC, id DESC
    LIMIT p_limit
    OFFSET p_offset
  )
  SELECT
    COALESCE(
      jsonb_agg(p.transfer ORDER BY p.transferred_at DESC, p.id DESC),
      '[]'::jsonb
    ) AS transfers,
    c.total_count
  FROM counted c
  LEFT JOIN paged p ON true
  GROUP BY c.total_count;
$function$;
