CREATE OR REPLACE FUNCTION public.get_in_process_timeline_count (
  p_chainid NUMERIC DEFAULT NULL,
  p_hidden BOOLEAN DEFAULT FALSE,
  p_mime TEXT DEFAULT NULL,
  p_period TEXT DEFAULT NULL,
  p_channel TEXT DEFAULT NULL,
  p_curated BOOLEAN DEFAULT FALSE,
  p_protocol TEXT DEFAULT NULL
) returns INTEGER language plpgsql stable AS $function$
DECLARE
  v_estimate real;
BEGIN
  IF p_chainid IS NULL
     AND p_hidden IS NOT TRUE
     AND p_mime IS NULL
     AND p_period IS NULL
     AND p_channel IS NULL
     AND p_curated IS NOT TRUE
     AND p_protocol IS NULL THEN
    SELECT reltuples INTO v_estimate
    FROM pg_class
    WHERE oid = 'public.in_process_moments'::regclass;

    IF v_estimate > 0 THEN
      RETURN v_estimate::int;
    END IF;
  END IF;

  RETURN (
    SELECT COUNT(*)::int
    FROM timeline_filtered_ids(p_chainid, p_hidden, p_mime, p_period, p_channel, p_curated, p_protocol)
  );
END;
$function$;
