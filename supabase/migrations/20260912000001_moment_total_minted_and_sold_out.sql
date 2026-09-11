ALTER TABLE public.in_process_moments
ADD COLUMN IF NOT EXISTS total_minted BIGINT NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.sync_moment_total_minted () returns trigger language plpgsql AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    UPDATE public.in_process_moments
    SET total_minted = total_minted + NEW.quantity
    WHERE id = NEW.moment;
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    IF NEW.moment IS DISTINCT FROM OLD.moment THEN
      UPDATE public.in_process_moments
      SET total_minted = GREATEST(total_minted - OLD.quantity, 0)
      WHERE id = OLD.moment;
      UPDATE public.in_process_moments
      SET total_minted = total_minted + NEW.quantity
      WHERE id = NEW.moment;
    ELSE
      UPDATE public.in_process_moments
      SET total_minted = GREATEST(total_minted + (NEW.quantity - OLD.quantity), 0)
      WHERE id = NEW.moment;
    END IF;
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    UPDATE public.in_process_moments
    SET total_minted = GREATEST(total_minted - OLD.quantity, 0)
    WHERE id = OLD.moment;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$;

DROP TRIGGER if EXISTS sync_moment_total_minted_trigger ON public.in_process_transfers;

CREATE TRIGGER sync_moment_total_minted_trigger
AFTER INSERT OR UPDATE OR DELETE ON public.in_process_transfers FOR EACH ROW
EXECUTE FUNCTION public.sync_moment_total_minted ();

-- Same 13-arg signature as 20260717000000 — REPLACE only, no DROP.
CREATE OR REPLACE FUNCTION public.build_moment_json (
  p_address TEXT,
  p_token_id NUMERIC,
  p_chain_id NUMERIC,
  p_protocol TEXT,
  p_id UUID,
  p_uri TEXT,
  p_creator TEXT,
  p_creator_username TEXT,
  p_collection UUID,
  p_metadata JSON,
  p_created_at TIMESTAMPTZ,
  p_sale JSON DEFAULT NULL,
  p_collection_name TEXT DEFAULT NULL
) returns JSON language sql stable AS $$
  SELECT json_build_object(
    'address',        p_address,
    'token_id',       p_token_id::text,
    'chain_id',       p_chain_id,
    'protocol',       p_protocol,
    'id',             p_id,
    'uri',            p_uri,
    'creator',        json_build_object('address', p_creator, 'username', p_creator_username),
    'collection',     json_build_object('name', p_collection_name),
    'admins',         COALESCE(get_moment_admins_json(p_collection, p_token_id), '[]'::json),
    'hidden',         COALESCE(
                        (SELECT json_agg(h.artist::text ORDER BY h.artist::text)
                         FROM in_process_hidden h WHERE h.moment = p_id),
                        '[]'::json
                      ),
    'created_at',     p_created_at,
    'metadata',       p_metadata,
    'sale',           p_sale,
    'comments',       (SELECT COUNT(*) FROM in_process_moment_comments c WHERE c.moment = p_id),
    'sold_out',       COALESCE(
                        (
                          SELECT m.max_supply > 0 AND m.total_minted >= m.max_supply
                          FROM in_process_moments m
                          WHERE m.id = p_id
                        ),
                        FALSE
                      )
  )
$$;
