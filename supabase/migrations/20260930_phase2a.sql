-- ============================================================
-- BeauTap Phase 2a: stylist booking links, stamp-card loyalty,
-- richer service details.
-- ============================================================

BEGIN;

-- ---------- booking links (@slug) ----------
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS slug text;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_slug_format;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_slug_format
  CHECK (slug IS NULL OR slug ~ '^[a-z0-9][a-z0-9-]{1,28}[a-z0-9]$');
CREATE UNIQUE INDEX IF NOT EXISTS uq_provider_slug ON provider_profiles (slug);

CREATE OR REPLACE FUNCTION public._slugify(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE WHEN length(s) >= 3 THEN s ELSE 'stylist' END
  FROM (SELECT trim(both '-' from substr(regexp_replace(lower(coalesce(t, '')), '[^a-z0-9]+', '-', 'g'), 1, 24)) AS s) x;
$$;

CREATE OR REPLACE FUNCTION public.provider_slug_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE base text; cand text; n int := 1;
BEGIN
  IF NEW.slug IS NOT NULL THEN
    NEW.slug := lower(trim(NEW.slug));
    IF NEW.slug IN ('admin', 'login', 'register', 'provider', 'providers', 'book', 'booking', 'bookings', 'home',
                    'browse', 'api', 'help', 'support', 'beautap', 'settings', 'account', 'verify', 'chat') THEN
      RAISE EXCEPTION 'That link name is reserved. Please choose another.';
    END IF;
    IF EXISTS (SELECT 1 FROM provider_profiles WHERE slug = NEW.slug AND provider_id <> NEW.provider_id) THEN
      RAISE EXCEPTION 'That link name is taken. Please choose another.';
    END IF;
    RETURN NEW;
  END IF;
  base := public._slugify((SELECT full_name FROM profiles WHERE id = NEW.provider_id));
  cand := base;
  WHILE EXISTS (SELECT 1 FROM provider_profiles WHERE slug = cand AND provider_id <> NEW.provider_id)
        OR cand IN ('admin', 'login', 'register', 'provider', 'book', 'home', 'browse', 'beautap') LOOP
    n := n + 1;
    cand := base || '-' || n;
  END LOOP;
  NEW.slug := cand;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_provider_slug ON provider_profiles;
CREATE TRIGGER trg_provider_slug BEFORE INSERT OR UPDATE OF slug ON provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.provider_slug_guard();

UPDATE provider_profiles SET slug = NULL WHERE slug IS NULL;

-- ---------- stamp-card loyalty ----------
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS loyalty_visits int NOT NULL DEFAULT 0;
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS loyalty_percent int NOT NULL DEFAULT 0;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_loyalty_check;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_loyalty_check
  CHECK ((loyalty_visits = 0 OR loyalty_visits BETWEEN 2 AND 20) AND loyalty_percent BETWEEN 0 AND 100);
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS loyalty_discount numeric(10,2) NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.loyalty_status(p_provider uuid, p_client uuid DEFAULT NULL) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  who uuid := coalesce(p_client, auth.uid());
  needed int; pct int; done int; used int; earned int;
BEGIN
  IF who IS DISTINCT FROM auth.uid() AND auth.uid() IS NOT NULL AND auth.uid() <> p_provider THEN
    who := auth.uid();
  END IF;
  SELECT loyalty_visits, loyalty_percent INTO needed, pct FROM provider_profiles WHERE provider_id = p_provider;
  IF coalesce(needed, 0) = 0 OR coalesce(pct, 0) = 0 OR who IS NULL THEN
    RETURN jsonb_build_object('enabled', false, 'available', false);
  END IF;
  SELECT count(*) INTO done FROM bookings WHERE client_id = who AND provider_id = p_provider AND status = 'completed';
  SELECT count(*) INTO used FROM bookings
   WHERE client_id = who AND provider_id = p_provider AND loyalty_discount > 0 AND status <> 'cancelled';
  earned := done / needed;
  RETURN jsonb_build_object(
    'enabled', true, 'visits_needed', needed, 'percent', pct, 'completed', done,
    'progress', done - (earned * needed), 'available', earned > used);
END;
$$;

CREATE OR REPLACE FUNCTION public._booking_total(b bookings) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(greatest(public._booking_base_price(b) - coalesce(b.discount_amount, 0) - coalesce(b.loyalty_discount, 0), 0)
               + coalesce(b.addons_total, 0) + coalesce(b.travel_fee, 0), 2);
$$;

CREATE OR REPLACE FUNCTION public.bookings_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  svc services;
  pp provider_profiles;
  promo record;
  km double precision;
  is_client boolean;
  is_prov boolean;
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;

  IF TG_OP = 'INSERT' THEN
    IF coalesce((auth.jwt() ->> 'is_anonymous')::boolean, false) THEN
      IF coalesce((SELECT nullif(trim(phone), '') FROM profiles WHERE id = uid), '') = '' THEN
        RAISE EXCEPTION 'Please add your phone number so the stylist can reach you';
      END IF;
      IF (SELECT count(*) FROM bookings WHERE client_id = uid AND status IN ('pending', 'confirmed')) >= 2 THEN
        RAISE EXCEPTION 'Create a free account to make more bookings';
      END IF;
    END IF;
    IF NOT public.provider_can_accept(NEW.provider_id) THEN
      RAISE EXCEPTION 'This stylist is fully booked this month. Please try another stylist.';
    END IF;
    SELECT * INTO svc FROM services WHERE id = NEW.service_id AND provider_id = NEW.provider_id;
    IF NOT FOUND OR NOT coalesce(svc.is_active, true) THEN
      RAISE EXCEPTION 'Service not available';
    END IF;
    IF NEW.tier_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM service_tiers WHERE id = NEW.tier_id AND service_id = NEW.service_id AND is_active) THEN
      RAISE EXCEPTION 'Option not available';
    END IF;
    IF NEW.package_id IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM service_packages WHERE id = NEW.package_id AND provider_id = NEW.provider_id AND is_active) THEN
      RAISE EXCEPTION 'Package not available';
    END IF;
    IF NEW.booking_time < now() THEN
      RAISE EXCEPTION 'Please choose a time in the future';
    END IF;

    NEW.status := 'pending';
    NEW.payment_status := 'unpaid';
    NEW.reminder_sent := false;
    NEW.agreed_price := NULL;
    NEW.provider_counter_price := NULL;
    NEW.cancelled_by := NULL; NEW.cancelled_at := NULL; NEW.cancellation_fee := 0;
    NEW.no_show_by := NULL; NEW.no_show_at := NULL;
    NEW.provider_arrived_at := NULL; NEW.service_started_at := NULL; NEW.service_completed_at := NULL;
    NEW.en_route_at := NULL; NEW.arrived_at := NULL;
    NEW.addons_total := 0;                       -- set by booking_addons trigger

    NEW.client_offered_price := NULL;          -- price offers retired; use service requests
    NEW.negotiation_status := 'none';
    NEW.negotiation_rounds := 0;
    NEW.offer_expires_at := NULL;
    NEW.deposit_paid := false;
    NEW.rescheduled_at := NULL;

    NEW.discount_amount := 0;
    IF NEW.promo_code IS NOT NULL AND trim(NEW.promo_code) <> '' THEN
      SELECT * INTO promo FROM public.check_promo(NEW.provider_id, NEW.promo_code, public._booking_base_price(NEW));
      IF promo.error IS NOT NULL THEN RAISE EXCEPTION '%', promo.error; END IF;
      UPDATE promotions SET used_count = coalesce(used_count, 0) + 1
       WHERE id = promo.promo_id AND (max_uses IS NULL OR coalesce(used_count, 0) < max_uses);
      IF NOT FOUND THEN RAISE EXCEPTION 'This promo code has reached its limit'; END IF;
      NEW.discount_amount := promo.discount;
    ELSE
      NEW.promo_code := NULL;
    END IF;

    NEW.travel_fee := 0;
    SELECT * INTO pp FROM provider_profiles WHERE provider_id = NEW.provider_id;
    IF NEW.client_lat IS NOT NULL AND NEW.client_lng IS NOT NULL
       AND pp.latitude IS NOT NULL AND pp.longitude IS NOT NULL
       AND coalesce(pp.travel_fee_per_km, 0) > 0 THEN
      km := public._haversine_km(pp.latitude, pp.longitude, NEW.client_lat, NEW.client_lng);
      NEW.travel_fee := round(least(coalesce(pp.max_travel_fee, 20),
                                    greatest(0, km - coalesce(pp.free_travel_radius_km, 0)) * pp.travel_fee_per_km)::numeric, 2);
    END IF;

    NEW.loyalty_discount := 0;
    IF (public.loyalty_status(NEW.provider_id, uid) ->> 'available')::boolean THEN
      NEW.loyalty_discount := round(public._booking_base_price(NEW)
        * (SELECT loyalty_percent FROM provider_profiles WHERE provider_id = NEW.provider_id) / 100.0, 2);
    END IF;

    NEW.total_price := public._booking_total(NEW);
    NEW.deposit_amount := public._deposit_for(NEW.provider_id, NEW.total_price);
    RETURN NEW;
  END IF;

  -- UPDATE ---------------------------------------------------
  is_client := uid = OLD.client_id;
  is_prov := uid = OLD.provider_id;

  -- Fields nobody edits directly
  NEW.client_id := OLD.client_id;           NEW.provider_id := OLD.provider_id;
  NEW.service_id := OLD.service_id;         NEW.package_id := OLD.package_id;
  NEW.created_at := OLD.created_at;         NEW.discount_amount := OLD.discount_amount;
  NEW.promo_code := OLD.promo_code;         NEW.addons_total := OLD.addons_total;
  NEW.travel_fee := OLD.travel_fee;         NEW.client_offered_price := OLD.client_offered_price;
  NEW.cancellation_fee := OLD.cancellation_fee;
  NEW.no_show_by := OLD.no_show_by;         NEW.no_show_at := OLD.no_show_at;
  NEW.reminder_sent := OLD.reminder_sent;   NEW.client_lat := OLD.client_lat;
  NEW.client_lng := OLD.client_lng;
  NEW.tier_id := OLD.tier_id;               NEW.ref := OLD.ref;
  NEW.deposit_paid := OLD.deposit_paid;     NEW.rescheduled_at := OLD.rescheduled_at;
  NEW.loyalty_discount := OLD.loyalty_discount;

  IF is_client THEN
    NEW.booking_time := OLD.booking_time;
    NEW.payment_status := OLD.payment_status;
    NEW.provider_counter_price := OLD.provider_counter_price;
    NEW.negotiation_rounds := OLD.negotiation_rounds;
    NEW.offer_expires_at := OLD.offer_expires_at;
    NEW.provider_arrived_at := OLD.provider_arrived_at;
    NEW.service_started_at := OLD.service_started_at;
    NEW.service_completed_at := OLD.service_completed_at;
    NEW.en_route_at := OLD.en_route_at;
    NEW.arrived_at := OLD.arrived_at;
    IF OLD.payment_status <> 'unpaid' THEN NEW.payment_method := OLD.payment_method; END IF;

    -- Client answers the provider's counter-offer
    IF NEW.negotiation_status IS DISTINCT FROM OLD.negotiation_status THEN
      IF OLD.negotiation_status = 'provider_countered' AND NEW.negotiation_status IN ('agreed', 'declined') THEN
        IF NEW.negotiation_status = 'agreed' THEN
          NEW.agreed_price := OLD.provider_counter_price;
        END IF;
      ELSE
        NEW.negotiation_status := OLD.negotiation_status;
      END IF;
    END IF;
    IF NEW.negotiation_status IS NOT DISTINCT FROM OLD.negotiation_status THEN
      NEW.agreed_price := OLD.agreed_price;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF NEW.status = 'cancelled' AND OLD.status = 'pending' THEN
        NEW.cancelled_by := 'client';
        NEW.cancelled_at := now();
      ELSE
        RAISE EXCEPTION 'Not allowed to change booking status';
      END IF;
    ELSE
      NEW.cancelled_by := OLD.cancelled_by;
      NEW.cancelled_at := OLD.cancelled_at;
    END IF;

  ELSIF is_prov THEN
    NEW.booking_time := OLD.booking_time;
    NEW.address := OLD.address;
    NEW.client_note := OLD.client_note;
    NEW.payment_method := OLD.payment_method;

    -- Providers can only record that they were paid (cash)
    IF NEW.payment_status IS DISTINCT FROM OLD.payment_status
       AND NOT (NEW.payment_status = 'paid' AND OLD.payment_status IN ('unpaid', 'cod_pending')) THEN
      NEW.payment_status := OLD.payment_status;
    END IF;

    IF NEW.negotiation_status IS DISTINCT FROM OLD.negotiation_status THEN
      IF OLD.negotiation_status = 'client_offered' AND NEW.negotiation_status = 'agreed' THEN
        NEW.agreed_price := OLD.client_offered_price;
      ELSIF OLD.negotiation_status IN ('client_offered', 'provider_countered') AND NEW.negotiation_status = 'declined' THEN
        NEW.agreed_price := OLD.agreed_price;
      ELSIF coalesce(OLD.negotiation_status, 'none') IN ('none', 'client_offered', 'provider_countered')
            AND NEW.negotiation_status = 'provider_countered' THEN
        IF NEW.provider_counter_price IS NULL OR NEW.provider_counter_price <= 0 THEN
          RAISE EXCEPTION 'Invalid counter-offer';
        END IF;
        IF coalesce(OLD.negotiation_rounds, 0) >= 3 THEN
          RAISE EXCEPTION 'Maximum negotiation rounds reached';
        END IF;
        NEW.negotiation_rounds := coalesce(OLD.negotiation_rounds, 0) + 1;
        NEW.agreed_price := OLD.agreed_price;
      ELSE
        RAISE EXCEPTION 'Invalid negotiation change';
      END IF;
    ELSE
      NEW.agreed_price := OLD.agreed_price;
      NEW.provider_counter_price := OLD.provider_counter_price;
      NEW.negotiation_rounds := OLD.negotiation_rounds;
    END IF;

    IF NEW.status IS DISTINCT FROM OLD.status THEN
      IF (OLD.status = 'pending' AND NEW.status IN ('confirmed', 'cancelled'))
         OR (OLD.status = 'confirmed' AND NEW.status IN ('completed', 'cancelled')) THEN
        IF NEW.status = 'cancelled' THEN
          NEW.cancelled_by := 'provider';
          NEW.cancelled_at := now();
        END IF;
      ELSE
        RAISE EXCEPTION 'Not allowed to change booking status';
      END IF;
    ELSE
      NEW.cancelled_by := OLD.cancelled_by;
      NEW.cancelled_at := OLD.cancelled_at;
    END IF;
  ELSE
    RAISE EXCEPTION 'Not allowed';
  END IF;

  NEW.total_price := public._booking_total(NEW);
  NEW.deposit_amount := CASE WHEN OLD.deposit_paid THEN OLD.deposit_amount
                             ELSE public._deposit_for(NEW.provider_id, NEW.total_price) END;
  RETURN NEW;
END;
$$;

-- ---------- richer service details ----------
ALTER TABLE services ADD COLUMN IF NOT EXISTS description text;
ALTER TABLE services ADD COLUMN IF NOT EXISTS includes text;
ALTER TABLE services ADD COLUMN IF NOT EXISTS aftercare text;
ALTER TABLE services ADD COLUMN IF NOT EXISTS image_url text;

INSERT INTO storage.buckets (id, name, public) VALUES ('service-images', 'service-images', true)
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS "Service images are public" ON storage.objects;
CREATE POLICY "Service images are public" ON storage.objects FOR SELECT USING (bucket_id = 'service-images');
DROP POLICY IF EXISTS "Stylists upload own service images" ON storage.objects;
CREATE POLICY "Stylists upload own service images" ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'service-images' AND auth.role() = 'authenticated'
              AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Stylists update own service images" ON storage.objects;
CREATE POLICY "Stylists update own service images" ON storage.objects FOR UPDATE
  USING (bucket_id = 'service-images' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Stylists delete own service images" ON storage.objects;
CREATE POLICY "Stylists delete own service images" ON storage.objects FOR DELETE
  USING (bucket_id = 'service-images' AND (storage.foldername(name))[1] = auth.uid()::text);

REVOKE ALL ON FUNCTION public.loyalty_status(uuid, uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.loyalty_status(uuid, uuid) TO anon, authenticated;

COMMIT;
