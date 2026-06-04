-- Optimize in_process_payments query performance:
-- 1. Add missing indexes on high-cardinality join/filter columns
-- 2. Rewrite RPC: separate lightweight count query (3 JOINs only) from
--    the data query, replacing COUNT(*) OVER() which forced a full-table
--    scan through all 5 JOINs before returning any data.
-- 3. Skip metadata JOIN in the count query when no mime filter is active.
-- Index on ORDER BY column — lets the data query use an index scan and
-- return the first LIMIT rows without touching the rest of the table.
CREATE INDEX if NOT EXISTS idx_payments_transferred_at_desc ON public.in_process_payments USING btree (transferred_at DESC);

-- Index on the FK join column (PostgreSQL does NOT create FK indexes automatically).
CREATE INDEX if NOT EXISTS idx_payments_moment ON public.in_process_payments USING btree (moment);

-- Index for collector filter (p.buyer = ANY(p_collectors))
CREATE INDEX if NOT EXISTS idx_payments_buyer ON public.in_process_payments USING btree (buyer);

-- Index for artist filter (c.creator = ANY(p_artists))
CREATE INDEX if NOT EXISTS idx_collections_creator ON public.in_process_collections USING btree (creator);

-- Rewrite RPC ------------------------------------------------------------
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
  capped_limit  int  := GREATEST(1, LEAST(COALESCE(NULLIF(p_limit, 0), 20), 100));
  clamped_page  int  := GREATEST(1, COALESCE(NULLIF(p_page, 0), 1));
  offset_val    int  := (clamped_page - 1) * capped_limit;
  v_payments    json;
  v_total_count int  := 0;
  v_total_pages int;
  has_artists   bool := (p_artists   IS NOT NULL AND COALESCE(array_length(p_artists,   1), 0) > 0);
  has_collectors bool := (p_collectors IS NOT NULL AND COALESCE(array_length(p_collectors, 1), 0) > 0);
BEGIN
  -- ── Count query (lightweight: 3 JOINs only) ───────────────────────────
  -- Omits artists, sales, fee_recipients joins — only what the WHERE clause needs.
  -- Skips metadata join entirely when no mime filter is active.
  IF p_mime IS NULL THEN
    SELECT COUNT(*) INTO v_total_count
    FROM in_process_payments p
    INNER JOIN in_process_moments m     ON p.moment     = m.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND (
        (NOT has_artists AND NOT has_collectors)
        OR (    has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        OR (NOT has_artists AND     has_collectors AND p.buyer   = ANY(p_collectors))
        OR (    has_artists AND     has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000';
  ELSE
    SELECT COUNT(*) INTO v_total_count
    FROM in_process_payments p
    INNER JOIN in_process_moments m     ON p.moment     = m.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    LEFT  JOIN in_process_metadata meta ON meta.moment  = m.id
    WHERE
      (p_chainid IS NULL OR c.chain_id = p_chainid)
      AND meta.content->>'mime' LIKE p_mime
      AND (
        (NOT has_artists AND NOT has_collectors)
        OR (    has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        OR (NOT has_artists AND     has_collectors AND p.buyer   = ANY(p_collectors))
        OR (    has_artists AND     has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000';
  END IF;

  -- ── Data query (fast: index scan on transferred_at + small LIMIT) ─────
  SELECT
    COALESCE(json_agg(row_data.moment_json ORDER BY row_data.transferred_at DESC), '[]'::json)
  INTO v_payments
  FROM (
    SELECT
      json_build_object(
        'id',               p.id,
        'amount',           p.amount::text,
        'currency',         s.currency,
        'transaction_hash', p.transaction_hash,
        'transferred_at',   p.transferred_at,
        'moment', json_build_object(
          'id',             m.id,
          'token_id',       m.token_id,
          'uri',            m.uri,
          'collection', json_build_object(
            'address',  c.address,
            'chain_id', c.chain_id,
            'creator',  c.creator
          ),
          'fee_recipients', COALESCE(fr.fee_recipients_array, '[]'::json),
          'metadata',       to_jsonb(meta)
        ),
        'buyer', json_build_object(
          'address',  b.address,
          'username', b.username
        )
      ) AS moment_json,
      p.transferred_at
    FROM in_process_payments p
    INNER JOIN in_process_moments m     ON p.moment     = m.id
    INNER JOIN in_process_collections c ON m.collection = c.id
    INNER JOIN in_process_artists b     ON p.buyer      = b.address
    INNER JOIN in_process_sales s       ON s.moment     = m.id
    LEFT  JOIN in_process_metadata meta ON meta.moment  = m.id
    LEFT  JOIN LATERAL (
      SELECT json_agg(
        json_build_object(
          'artist_address',     fr.artist_address,
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
        OR (    has_artists AND NOT has_collectors AND c.creator = ANY(p_artists))
        OR (NOT has_artists AND     has_collectors AND p.buyer   = ANY(p_collectors))
        OR (    has_artists AND     has_collectors AND (c.creator = ANY(p_artists) OR p.buyer = ANY(p_collectors)))
      )
      AND p.buyer != '0x0000000000000000000000000000000000000000'
    ORDER BY p.transferred_at DESC
    LIMIT capped_limit OFFSET offset_val
  ) row_data;

  v_total_pages := CASE
    WHEN v_total_count > 0 THEN CEIL(v_total_count::numeric / capped_limit)
    ELSE 1
  END;

  RETURN json_build_object(
    'payments', v_payments,
    'count',    v_total_count,
    'pagination', json_build_object(
      'page',        clamped_page,
      'limit',       capped_limit,
      'total_pages', v_total_pages
    )
  );
END;
$function$;
