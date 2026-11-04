ALTER TABLE public.in_process_moments
ADD COLUMN released_at TIMESTAMPTZ;

CREATE OR REPLACE FUNCTION public.moment_released_at (p_moment UUID, p_created_at TIMESTAMPTZ) returns TIMESTAMPTZ language sql stable AS $function$
  SELECT COALESCE(
    (
      SELECT to_timestamp(s.sale_start::double precision)
      FROM in_process_sales s
      WHERE s.moment = p_moment
        AND s.sale_start <> 0
      ORDER BY s.schedule_num NULLS FIRST
      LIMIT 1
    ),
    p_created_at
  )
$function$;

CREATE OR REPLACE FUNCTION public.set_moment_released_at () returns trigger language plpgsql AS $function$
BEGIN
  NEW.released_at := public.moment_released_at(NEW.id, NEW.created_at);
  RETURN NEW;
END;
$function$;

CREATE TRIGGER set_moment_released_at
BEFORE INSERT OR UPDATE OF created_at ON public.in_process_moments FOR EACH ROW
EXECUTE FUNCTION public.set_moment_released_at ();

CREATE OR REPLACE FUNCTION public.sync_moment_released_at () returns trigger language plpgsql AS $function$
BEGIN
  IF TG_OP IN ('INSERT', 'UPDATE') THEN
    UPDATE public.in_process_moments m
    SET released_at = public.moment_released_at(m.id, m.created_at)
    WHERE m.id = NEW.moment
      AND m.released_at IS DISTINCT FROM public.moment_released_at(m.id, m.created_at);
  END IF;

  IF TG_OP = 'DELETE' OR (TG_OP = 'UPDATE' AND OLD.moment IS DISTINCT FROM NEW.moment) THEN
    UPDATE public.in_process_moments m
    SET released_at = public.moment_released_at(m.id, m.created_at)
    WHERE m.id = OLD.moment
      AND m.released_at IS DISTINCT FROM public.moment_released_at(m.id, m.created_at);
  END IF;

  RETURN NULL;
END;
$function$;

CREATE TRIGGER sync_moment_released_at
AFTER INSERT OR DELETE OR UPDATE OF sale_start,
moment,
schedule_num ON public.in_process_sales FOR EACH ROW
EXECUTE FUNCTION public.sync_moment_released_at ();

UPDATE public.in_process_moments m
SET
  released_at = public.moment_released_at (m.id, m.created_at);

ALTER TABLE public.in_process_moments
ALTER COLUMN released_at
SET DEFAULT NOW(),
ALTER COLUMN released_at
SET NOT NULL;
