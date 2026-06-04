-- Fix get_in_process_payments filter logic:
-- When only one of p_artists or p_collectors is provided, the other's IS NULL check
-- caused the entire OR condition to be TRUE, returning all payments instead of filtered.
DROP FUNCTION if EXISTS public.get_in_process_payments (INTEGER, INTEGER, TEXT[], TEXT[], NUMERIC, TEXT);

CREATE OR REPLACE FUNCTION public.get_in_process_payments (
  p_limit INTEGER DEFAULT 20,
  p_page INTEGER DEFAULT 1,
  p_artists TEXT[] DEFAULT NULL,
  p_collectors TEXT[] DEFAULT NULL,
  p_chainid NUMERIC DEFAULT 8453,
  p_mime TEXT DEFAULT NULL
) returns JSON language plpgsql AS $function$
DECLARE
  capped_limit int := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page int := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val int := (clamped_page - 1) * capped_limit;
  v_payments json;
  v_total_count int;
  v_total_pages int;
  has_artists bool := (p_artists IS NOT NULL AND COALESCE(array_length(p_artists, 1), 0) > 0);
  has_collectors bool := (p_collectors IS NOT NULL AND COALESCE(array_length(p_collectors, 1), 0) > 0);
BEGIN
  -- Get filtered count (for pagination calculation)
  WITH filtered_payments AS (
    SELECT DISTINCT
      p.id
    FROM in_process_payments p
    INNER JOIN in_process_moments m ON p.moment = m.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists b ON p.buyer = b.address
    INNER JOIN in_process_sales s ON s.moment = m.id
    LEFT JOIN in_process_metadata meta ON meta.moment = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (p_mime IS NULL OR meta.content->>'mime' LIKE p_mime)
      AND (
        -- Neither filter: show all
        (NOT has_artists AND NOT has_collectors)
        -- Artists filter only
        OR (has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        -- Collectors filter only
        OR (NOT has_artists AND has_collectors AND p.buyer = ANY(p_collectors))
        -- Both filters: OR (union of income + expense)
        OR (has_artists AND has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000'
  )
  SELECT COUNT(*) INTO v_total_count FROM filtered_payments;

  -- Get payments array with related data
  SELECT json_agg(
    json_build_object(
      'id', payment_result.id,
      'amount', payment_result.amount::text,
      'currency', payment_result.currency,
      'transaction_hash', payment_result.transaction_hash,
      'transferred_at', payment_result.transferred_at,
      'moment', payment_result.moment,
      'buyer', payment_result.buyer
    )
  ) INTO v_payments
  FROM (
    SELECT
      p.id,
      p.amount,
      s.currency,
      p.transaction_hash,
      p.transferred_at,
      json_build_object(
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
      ) AS moment,
      json_build_object(
        'address', b.address,
        'username', b.username
      ) AS buyer
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
        -- Neither filter: show all
        (NOT has_artists AND NOT has_collectors)
        -- Artists filter only
        OR (has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        -- Collectors filter only
        OR (NOT has_artists AND has_collectors AND p.buyer = ANY(p_collectors))
        -- Both filters: OR (union of income + expense)
        OR (has_artists AND has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000'
    ORDER BY p.transferred_at DESC
    LIMIT capped_limit OFFSET offset_val
  ) payment_result;

  -- Calculate total pages
  v_total_pages := CASE WHEN v_total_count > 0 THEN CEIL(v_total_count::numeric / capped_limit) ELSE 1 END;

  -- Return JSON response matching API format
  RETURN json_build_object(
    'payments', COALESCE(v_payments, '[]'::json),
    'count', v_total_count,
    'pagination', json_build_object(
      'page', clamped_page,
      'limit', capped_limit,
      'total_pages', v_total_pages
    )
  );
END;
$function$;
