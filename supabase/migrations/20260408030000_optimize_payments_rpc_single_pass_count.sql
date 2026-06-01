-- Optimize get_in_process_payments: replace double-query (separate COUNT + data fetch)
-- with a single-pass using COUNT(*) OVER() window function.
-- Previously the same 5-table JOIN ran twice — once with DISTINCT for counting,
-- once for data — doubling the query cost on every request.
DROP FUNCTION IF EXISTS public.get_in_process_payments(integer, integer, text[], text[], numeric, text);

CREATE OR REPLACE FUNCTION public.get_in_process_payments(
  p_limit integer DEFAULT 20,
  p_page integer DEFAULT 1,
  p_artists text[] DEFAULT NULL,
  p_collectors text[] DEFAULT NULL,
  p_chainid numeric DEFAULT 8453,
  p_mime text DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql
AS $function$
DECLARE
  capped_limit int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val int := (clamped_page - 1) * capped_limit;
  v_payments json;
  v_total_count int := 0;
  v_total_pages int;
  has_artists bool := (p_artists IS NOT NULL AND COALESCE(array_length(p_artists, 1), 0) > 0);
  has_collectors bool := (p_collectors IS NOT NULL AND COALESCE(array_length(p_collectors, 1), 0) > 0);
BEGIN
  -- Single-pass: compute total count and fetch page data together via window function
  SELECT
    COALESCE(json_agg(row_data.moment_json ORDER BY row_data.transferred_at DESC), '[]'::json),
    COALESCE(MAX(row_data.total_count), 0)
  INTO v_payments, v_total_count
  FROM (
    SELECT
      json_build_object(
        'id', p.id,
        'amount', p.amount::text,
        'currency', s.currency,
        'transaction_hash', p.transaction_hash,
        'transferred_at', p.transferred_at,
        'moment', json_build_object(
          'id', m.id,
          'token_id', m.token_id,
          'uri', m.uri,
          'collection', json_build_object(
            'address', c.address,
            'chain_id', c.chain_id,
            'creator', c.creator
          ),
          'fee_recipients', COALESCE(fr.fee_recipients_array, '[]'::json),
          'metadata', to_jsonb(meta)
        ),
        'buyer', json_build_object(
          'address', b.address,
          'username', b.username
        )
      ) AS moment_json,
      p.transferred_at,
      COUNT(*) OVER() AS total_count
    FROM in_process_payments p
    INNER JOIN in_process_moments m ON p.moment = m.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists b ON p.buyer = b.address
    INNER JOIN in_process_sales s ON s.moment = m.id
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    LEFT JOIN LATERAL (
      SELECT json_agg(
        json_build_object(
          'artist_address', fr.artist_address,
          'percent_allocation', fr.percent_allocation
        )
      ) AS fee_recipients_array
      FROM in_process_moment_fee_recipients fr
      WHERE fr.moment = m.id
    ) fr ON true
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND (
        (NOT has_artists AND NOT has_collectors)
        OR (has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        OR (NOT has_artists AND has_collectors AND p.buyer = ANY(p_collectors))
        OR (has_artists AND has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000'
    ORDER BY p.transferred_at DESC
    LIMIT capped_limit OFFSET offset_val
  ) row_data;

  -- Calculate total pages
  v_total_pages := CASE WHEN v_total_count > 0 THEN CEIL(v_total_count::numeric / capped_limit) ELSE 1 END;

  RETURN json_build_object(
    'payments', v_payments,
    'count', v_total_count,
    'pagination', json_build_object(
      'page', clamped_page,
      'limit', capped_limit,
      'total_pages', v_total_pages
    )
  );
END;
$function$
;
