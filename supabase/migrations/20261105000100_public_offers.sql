-- Pros can show an offer publicly: it appears in the Home banner and in
-- Browse, with its code filled in for the client. Offers not marked public
-- stay private codes, exactly as before.

ALTER TABLE promotions ADD COLUMN IF NOT EXISTS is_public boolean NOT NULL DEFAULT false;

-- Live public offers from pros clients can find. Read-only and limited to
-- what an advert needs.
CREATE OR REPLACE FUNCTION public.public_offers(p_limit int DEFAULT 20)
RETURNS TABLE (
  promo_id uuid,
  provider_id uuid,
  code text,
  description text,
  discount_type text,
  discount_value numeric,
  min_order_amount numeric,
  valid_until timestamptz,
  pro_name text,
  avatar_url text,
  area text,
  city text
)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p.id, p.provider_id, upper(p.code), p.description, p.discount_type, p.discount_value,
         coalesce(p.min_order_amount, 0), p.valid_until,
         pr.full_name, pr.avatar_url, pp.area, c.name
    FROM promotions p
    JOIN provider_profiles pp ON pp.provider_id = p.provider_id
    JOIN profiles pr ON pr.id = p.provider_id
    LEFT JOIN cities c ON c.id = pp.city_id
   WHERE p.is_public AND p.is_active
     AND (p.valid_from IS NULL OR p.valid_from <= now())
     AND (p.valid_until IS NULL OR p.valid_until >= now())
     AND (p.max_uses IS NULL OR coalesce(p.used_count, 0) < p.max_uses)
     AND NOT coalesce(pp.is_hidden, false)
     AND public.provider_has_location(p.provider_id)
   ORDER BY p.created_at DESC
   LIMIT least(greatest(coalesce(p_limit, 20), 1), 50);
$$;
GRANT EXECUTE ON FUNCTION public.public_offers(int) TO anon, authenticated;

-- Promo codes were readable by anyone, signed in or not. Only the pro who
-- made them (and admins) need the table: clients check codes through
-- check_promo() and see public offers through public_offers().
ALTER TABLE promotions ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname FROM pg_policies WHERE schemaname = 'public' AND tablename = 'promotions' LOOP
    EXECUTE format('DROP POLICY %I ON public.promotions', pol.policyname);
  END LOOP;
END $$;
CREATE POLICY promotions_owner ON public.promotions FOR ALL TO authenticated
  USING (provider_id = auth.uid() OR public.is_admin())
  WITH CHECK (provider_id = auth.uid() OR public.is_admin());
REVOKE ALL ON public.promotions FROM anon;
