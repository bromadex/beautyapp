-- Phase A: all of beauty — service groups, where services happen, massage and
-- medical rules, certificates, patch tests and age limits.

-- ───────────────── Service groups ─────────────────

CREATE TABLE IF NOT EXISTS service_groups (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL UNIQUE,
  icon text NOT NULL,             -- Tabler icon name, drawn by the app
  sort_order integer NOT NULL
);
ALTER TABLE service_groups ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read groups" ON service_groups;
CREATE POLICY "Anyone can read groups" ON service_groups FOR SELECT USING (true);

INSERT INTO service_groups(name, icon, sort_order) VALUES
  ('Hair', 'ripple', 1), ('Barbering', 'scissors', 2), ('Nails', 'hand_finger', 3),
  ('Lashes & Brows', 'eye', 4), ('Makeup', 'brush', 5), ('Skin', 'droplet', 6),
  ('Hair Removal', 'feather', 7), ('Body & Spa', 'leaf', 8), ('Glow', 'sun_high', 9),
  ('Body Art', 'palette', 10), ('Bridal & Events', 'diamond', 11)
ON CONFLICT (name) DO UPDATE SET icon = EXCLUDED.icon, sort_order = EXCLUDED.sort_order;

ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS group_id uuid REFERENCES service_groups(id);
-- Rules that come with a kind of service.
ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS studio_only boolean NOT NULL DEFAULT false;
ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS needs_certificate boolean NOT NULL DEFAULT false;
ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS patch_test boolean NOT NULL DEFAULT false;
ALTER TABLE service_categories ADD COLUMN IF NOT EXISTS min_age integer;

-- New categories so every beauty trade has a home.
INSERT INTO service_categories(name, sort_order)
SELECT n, 100 FROM unnest(ARRAY[
  'Cuts & Styling', 'Hair Treatments', 'Beard & Shave', 'Pedicure', 'Gel & Acrylics', 'Brows',
  'Microblading', 'Facials', 'Waxing', 'Threading', 'Sugaring', 'Body Scrubs & Wraps',
  'Reflexology', 'Spray Tan', 'Teeth Whitening', 'Henna', 'Events & Photoshoots']) AS n
WHERE NOT EXISTS (SELECT 1 FROM service_categories c WHERE c.name = n);

WITH m(cat, grp, ord) AS (VALUES
  ('Braids','Hair',1), ('Wigs','Hair',2), ('Weaves','Hair',3), ('Natural Hair','Hair',4), ('Locs','Hair',5),
  ('Relaxed Hair','Hair',6), ('Colour','Hair',7), ('Cuts & Styling','Hair',8), ('Hair Treatments','Hair',9),
  ('Kids Styles','Hair',10),
  ('Barber','Barbering',11), ('Beard & Shave','Barbering',12),
  ('Nails','Nails',13), ('Pedicure','Nails',14), ('Gel & Acrylics','Nails',15),
  ('Lashes','Lashes & Brows',16), ('Brows','Lashes & Brows',17), ('Microblading','Lashes & Brows',18),
  ('Makeup','Makeup',19),
  ('Skincare','Skin',20), ('Facials','Skin',21),
  ('Waxing','Hair Removal',22), ('Threading','Hair Removal',23), ('Sugaring','Hair Removal',24),
  ('Massage','Body & Spa',25), ('Body Scrubs & Wraps','Body & Spa',26), ('Reflexology','Body & Spa',27),
  ('Spray Tan','Glow',28), ('Teeth Whitening','Glow',29),
  ('Tattoo & Piercing','Body Art',30), ('Henna','Body Art',31),
  ('Bridal','Bridal & Events',32), ('Events & Photoshoots','Bridal & Events',33))
UPDATE service_categories c SET group_id = g.id, sort_order = m.ord, icon = NULL
  FROM m JOIN service_groups g ON g.name = m.grp
 WHERE c.name = m.cat;

UPDATE service_categories SET studio_only = true, needs_certificate = true WHERE name = 'Massage';
UPDATE service_categories SET studio_only = true, min_age = 18 WHERE name = 'Tattoo & Piercing';
UPDATE service_categories SET needs_certificate = true, patch_test = true WHERE name = 'Microblading';
UPDATE service_categories SET patch_test = true WHERE name IN ('Colour', 'Lashes', 'Facials', 'Waxing', 'Sugaring', 'Spray Tan', 'Relaxed Hair');

-- ───────────────── Services ─────────────────

ALTER TABLE services ADD COLUMN IF NOT EXISTS location_mode text NOT NULL DEFAULT 'client';
ALTER TABLE services DROP CONSTRAINT IF EXISTS services_location_mode_check;
ALTER TABLE services ADD CONSTRAINT services_location_mode_check CHECK (location_mode IN ('client', 'studio', 'either'));
ALTER TABLE services ADD COLUMN IF NOT EXISTS patch_test boolean NOT NULL DEFAULT false;
ALTER TABLE services ADD COLUMN IF NOT EXISTS review_status text NOT NULL DEFAULT 'ok';
ALTER TABLE services DROP CONSTRAINT IF EXISTS services_review_status_check;
ALTER TABLE services ADD CONSTRAINT services_review_status_check CHECK (review_status IN ('ok', 'flagged', 'rejected'));
ALTER TABLE services ADD COLUMN IF NOT EXISTS flag_reason text;

-- ───────────────── Pro title and certificates ─────────────────

ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS title text;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_profiles_title_check;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_profiles_title_check CHECK (title IS NULL OR length(title) <= 40);

CREATE TABLE IF NOT EXISTS provider_certificates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(title) BETWEEN 2 AND 80),
  issuer text CHECK (issuer IS NULL OR length(issuer) <= 80),
  year integer CHECK (year IS NULL OR year BETWEEN 1970 AND 2100),
  image_url text,
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE provider_certificates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can read certificates" ON provider_certificates;
CREATE POLICY "Anyone can read certificates" ON provider_certificates FOR SELECT USING (true);
DROP POLICY IF EXISTS "Pro manages own certificates" ON provider_certificates;
CREATE POLICY "Pro manages own certificates" ON provider_certificates FOR ALL
  USING (provider_id = auth.uid()) WITH CHECK (provider_id = auth.uid());

INSERT INTO storage.buckets (id, name, public) VALUES ('certificates', 'certificates', true)
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS "Pros upload own certificates" ON storage.objects;
CREATE POLICY "Pros upload own certificates" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'certificates' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Pros change own certificates" ON storage.objects;
CREATE POLICY "Pros change own certificates" ON storage.objects FOR UPDATE TO authenticated
  USING (bucket_id = 'certificates' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "Pros delete own certificates" ON storage.objects;
CREATE POLICY "Pros delete own certificates" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'certificates' AND (storage.foldername(name))[1] = auth.uid()::text);

-- ───────────────── Service rules ─────────────────

-- Sexual wording is never allowed. Medical treatments are held for admin review.
CREATE OR REPLACE FUNCTION public._blocked_words(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT (regexp_match(lower(coalesce(t, '')),
    '(sensual|nuru|tantric|tantra|happy ending|body[ -]to[ -]body|b2b massage|erotic|lingam|yoni|prostate|escort|sexual)'))[1];
$$;

CREATE OR REPLACE FUNCTION public._medical_words(t text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT (regexp_match(lower(coalesce(t, '')),
    '(botox|filler|inject|laser|prescription|iv drip|drip therapy|\mprp\M|mesotherapy|microneedl|dermal|glutathione|hydroquinone|skin lighten|lightening cream|bleaching cream|whitening cream|skin bleach|plasma pen|liposuction|anaesthe|anesthe)'))[1];
$$;

CREATE OR REPLACE FUNCTION public.services_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  cat service_categories;
  txt text := concat_ws(' ', NEW.service_name, NEW.description, NEW.includes, NEW.aftercare);
  bad text;
  med text;
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;

  SELECT * INTO cat FROM service_categories WHERE id = NEW.category_id;

  bad := public._blocked_words(txt);
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'The word "%" isn''t allowed on BeauTap. Only professional services can be listed.', bad;
  END IF;

  IF cat.studio_only THEN NEW.location_mode := 'studio'; END IF;
  NEW.patch_test := coalesce(NEW.patch_test, false) OR coalesce(cat.patch_test, false);

  IF cat.needs_certificate AND coalesce(NEW.is_active, true) THEN
    IF NOT coalesce((SELECT is_business_verified FROM profiles WHERE id = NEW.provider_id), false) THEN
      RAISE EXCEPTION '% needs a verified business. Verify your business in Business settings first.', cat.name;
    END IF;
    IF NOT EXISTS (SELECT 1 FROM provider_certificates WHERE provider_id = NEW.provider_id) THEN
      RAISE EXCEPTION '% needs a certificate. Add one in Business settings first.', cat.name;
    END IF;
  END IF;

  -- Pros can't set the review result themselves.
  IF TG_OP = 'UPDATE' THEN
    NEW.review_status := OLD.review_status;
    NEW.flag_reason := OLD.flag_reason;
  ELSE
    NEW.review_status := 'ok';
    NEW.flag_reason := NULL;
  END IF;
  IF NEW.review_status <> 'rejected'
     AND (TG_OP = 'INSERT' OR txt IS DISTINCT FROM concat_ws(' ', OLD.service_name, OLD.description, OLD.includes, OLD.aftercare)) THEN
    med := public._medical_words(txt);
    IF med IS NOT NULL THEN
      NEW.review_status := 'flagged';
      NEW.flag_reason := 'Mentions "' || med || '". Medical treatments aren''t allowed on BeauTap.';
    ELSE
      NEW.review_status := 'ok';
      NEW.flag_reason := NULL;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_services_guard ON services;
CREATE TRIGGER trg_services_guard BEFORE INSERT OR UPDATE ON services
  FOR EACH ROW EXECUTE FUNCTION public.services_guard();

-- Clients only see services that passed review.
DROP POLICY IF EXISTS "Anyone can read active services" ON services;
DROP POLICY IF EXISTS "Anyone can read services" ON services;
CREATE POLICY "Anyone can read reviewed services" ON services FOR SELECT
  USING (review_status = 'ok' OR provider_id = auth.uid() OR public.is_admin());

-- Admin decision on a flagged service.
CREATE OR REPLACE FUNCTION public.review_service(p_service uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s services;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admins only'; END IF;
  PERFORM public._bypass();
  UPDATE services SET review_status = CASE WHEN p_approve THEN 'ok' ELSE 'rejected' END,
         flag_reason = CASE WHEN p_approve THEN NULL ELSE coalesce(nullif(trim(p_note), ''), flag_reason) END,
         is_active = CASE WHEN p_approve THEN is_active ELSE false END
   WHERE id = p_service RETURNING * INTO s;
  IF FOUND THEN
    INSERT INTO notifications(user_id, type, title, body, reference_id)
    VALUES (s.provider_id, 'service_review',
            CASE WHEN p_approve THEN 'Service approved' ELSE 'Service not allowed' END,
            CASE WHEN p_approve THEN s.service_name || ' is now visible to clients.'
                 ELSE s.service_name || ' can''t be listed. ' || coalesce(s.flag_reason, 'Medical treatments aren''t allowed on BeauTap.') END,
            s.id::text);
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.review_service(uuid, boolean, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.review_service(uuid, boolean, text) TO authenticated;

-- ───────────────── Bookings: studio visits and client agreement ─────────────────

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS at_studio boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_ack boolean NOT NULL DEFAULT false;

-- Reports: sexual or inappropriate conduct.
ALTER TABLE disputes DROP CONSTRAINT IF EXISTS disputes_category_check;
ALTER TABLE disputes ADD CONSTRAINT disputes_category_check
  CHECK (category IN ('service_problem', 'payment_issue', 'no_show', 'misconduct', 'sexual_conduct', 'other'));

-- "Beauty pro" wording in server messages; bookings honour studio visits,
-- the client agreement and service review.
CREATE OR REPLACE FUNCTION public._notify_waitlist(p_provider uuid, p_day date)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE w record; pname text;
BEGIN
  IF p_day < (now() AT TIME ZONE 'Africa/Harare')::date THEN RETURN; END IF;
  SELECT full_name INTO pname FROM profiles WHERE id = p_provider;
  FOR w IN SELECT * FROM waitlist
            WHERE provider_id = p_provider AND day = p_day AND notified_at IS NULL
            ORDER BY created_at LOOP
    IF EXISTS (SELECT 1 FROM public.available_slots(p_provider, p_day, w.minutes)) THEN
      INSERT INTO notifications(user_id, type, title, body, reference_id)
      VALUES (w.client_id, 'waitlist', 'A time just opened',
              coalesce(pname, 'Your pro') || ' has a free time on ' || to_char(p_day, 'Dy DD Mon')
                || '. Book it before someone else does.',
              p_provider::text || '|' || coalesce(w.service_id::text, ''));
      UPDATE waitlist SET notified_at = now() WHERE id = w.id;
    END IF;
  END LOOP;
END $function$;
CREATE OR REPLACE FUNCTION public.accept_quote(p_quote_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE q service_request_quotes; r service_requests; svc_id uuid; bk uuid; when_ts timestamptz;
BEGIN
  SELECT * INTO q FROM service_request_quotes WHERE id = p_quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  SELECT * INTO r FROM service_requests WHERE id = q.request_id FOR UPDATE;
  IF r.client_id <> auth.uid() THEN RAISE EXCEPTION 'Quote not found'; END IF;
  IF r.status <> 'open' OR q.status <> 'pending' THEN RAISE EXCEPTION 'This request is no longer open'; END IF;
  IF NOT public.provider_can_accept(q.provider_id) THEN
    RAISE EXCEPTION 'This pro is not accepting bookings right now';
  END IF;

  SELECT id INTO svc_id FROM services
   WHERE provider_id = q.provider_id AND coalesce(is_active, true)
   ORDER BY (category_id IS NOT DISTINCT FROM r.category_id) DESC, created_at
   LIMIT 1;
  IF svc_id IS NULL THEN RAISE EXCEPTION 'This pro has no active services'; END IF;

  when_ts := CASE WHEN r.preferred_date IS NOT NULL
                  THEN ((r.preferred_date + coalesce(r.preferred_time, time '10:00')) AT TIME ZONE 'Africa/Harare')
                  ELSE now() + interval '1 day' END;
  IF when_ts < now() THEN when_ts := now() + interval '1 day'; END IF;

  PERFORM public._bypass();
  UPDATE service_request_quotes SET status = CASE WHEN id = q.id THEN 'accepted' ELSE 'declined' END
   WHERE request_id = r.id AND status = 'pending';
  UPDATE service_requests SET status = 'booked' WHERE id = r.id;

  INSERT INTO bookings (client_id, provider_id, service_id, booking_time, address, status,
                        total_price, agreed_price, negotiation_status, client_note, payment_method)
  VALUES (r.client_id, q.provider_id, svc_id, when_ts, r.location, 'pending',
          q.quoted_price, q.quoted_price, 'agreed',
          'From request: ' || r.title || coalesce(E'\n' || r.description, ''), 'cash')
  RETURNING id INTO bk;
  UPDATE bookings SET deposit_amount = public._deposit_for(q.provider_id, q.quoted_price) WHERE id = bk;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (q.provider_id, 'booking', 'Quote Accepted!',
          format('Your $%s quote for "%s" was accepted. Please confirm the booking.', q.quoted_price, r.title),
          bk::text);
  RETURN bk;
END;
$function$;
CREATE OR REPLACE FUNCTION public.booking_after_update()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE sname text; pname text;
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.client_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM reviews WHERE booking_id = NEW.id) THEN
    SELECT full_name INTO pname FROM profiles WHERE id = NEW.provider_id;
    SELECT service_name INTO sname FROM services WHERE id = NEW.service_id;
    INSERT INTO notifications(user_id, type, title, body, reference_id)
    VALUES (NEW.client_id, 'review_request', 'How was your ' || coalesce(sname, 'appointment') || '?',
            'Rate ' || coalesce(pname, 'your pro') || ' in 10 seconds. It helps other clients choose.',
            NEW.id::text);
  END IF;

  IF (NEW.status = 'cancelled' AND OLD.status IN ('pending', 'confirmed'))
     OR (NEW.booking_time IS DISTINCT FROM OLD.booking_time AND OLD.status IN ('pending', 'confirmed')) THEN
    PERFORM public._notify_waitlist(OLD.provider_id, (OLD.booking_time AT TIME ZONE 'Africa/Harare')::date);
  END IF;
  RETURN NULL;
END $function$;
CREATE OR REPLACE FUNCTION public.bookings_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
        RAISE EXCEPTION 'Please add your phone number so the pro can reach you';
      END IF;
      IF (SELECT count(*) FROM bookings WHERE client_id = uid AND status IN ('pending', 'confirmed')) >= 2 THEN
        RAISE EXCEPTION 'Create a free account to make more bookings';
      END IF;
    END IF;
    IF NOT public.provider_can_accept(NEW.provider_id) THEN
      RAISE EXCEPTION 'This pro is fully booked this month. Please try another pro.';
    END IF;
    SELECT * INTO svc FROM services WHERE id = NEW.service_id AND provider_id = NEW.provider_id;
    IF NOT FOUND OR NOT coalesce(svc.is_active, true) THEN
      RAISE EXCEPTION 'Service not available';
    END IF;
    IF svc.review_status <> 'ok' THEN
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

    IF svc.location_mode = 'studio' THEN NEW.at_studio := true;
    ELSIF svc.location_mode = 'client' THEN NEW.at_studio := false;
    END IF;
    IF NEW.at_studio THEN
      NEW.travel_fee := 0;
      NEW.address := coalesce(nullif(trim(pp.address), ''), 'At the pro''s studio');
    END IF;
    IF EXISTS (SELECT 1 FROM service_categories c WHERE c.id = svc.category_id
                AND ((c.studio_only AND c.needs_certificate) OR c.min_age IS NOT NULL))
       AND NOT coalesce(NEW.client_ack, false) THEN
      RAISE EXCEPTION 'Please accept the booking terms for this service';
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
  NEW.at_studio := OLD.at_studio;           NEW.client_ack := OLD.client_ack;

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
$function$;
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'This booking can no longer be cancelled';
  END IF;
  by_client := auth.uid() = b.client_id;

  IF by_client AND b.status = 'confirmed' THEN
    SELECT * INTO pol FROM cancellation_policies WHERE provider_id = b.provider_id;
    IF FOUND AND b.booking_time - now() < make_interval(hours => pol.free_cancel_hours) THEN
      fee := round(b.total_price * pol.late_cancel_fee_percent / 100.0, 2);
    END IF;
  END IF;

  PERFORM public._bypass();
  UPDATE bookings SET status = 'cancelled',
         cancelled_by = CASE WHEN by_client THEN 'client' ELSE 'provider' END,
         cancelled_at = now(), cancel_reason = nullif(trim(p_reason), ''),
         cancellation_fee = fee
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_client THEN b.provider_id ELSE b.client_id END, 'booking',
          'Booking Cancelled',
          CASE WHEN by_client THEN 'The client cancelled their booking.' ELSE 'Your pro cancelled the booking.' END
          || coalesce(' Reason: ' || nullif(trim(p_reason), ''), '')
          || CASE WHEN fee > 0 THEN format(' Late cancellation fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$function$;
CREATE OR REPLACE FUNCTION public.check_slot(p_provider uuid, p_start timestamp with time zone, p_minutes integer, p_ignore_booking uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  local_start timestamp := p_start AT TIME ZONE 'Africa/Harare';
  local_end   timestamp := (p_start + make_interval(mins => p_minutes)) AT TIME ZONE 'Africa/Harare';
  av provider_availability;
  buf int := coalesce((SELECT buffer_minutes FROM provider_profiles WHERE provider_id = p_provider), 0);
  notice int := coalesce((SELECT min_notice_hours FROM provider_profiles WHERE provider_id = p_provider), 2);
  advance int := coalesce((SELECT max_advance_days FROM provider_profiles WHERE provider_id = p_provider), 60);
BEGIN
  IF p_start < now() + make_interval(hours => notice) THEN
    RETURN format('This pro needs at least %s hour%s notice.', notice, CASE WHEN notice = 1 THEN '' ELSE 's' END);
  END IF;
  IF p_start > now() + make_interval(days => advance) THEN
    RETURN format('This pro takes bookings up to %s days ahead.', advance);
  END IF;

  IF EXISTS (SELECT 1 FROM provider_blocked_dates
              WHERE provider_id = p_provider AND blocked_date = local_start::date) THEN
    RETURN 'The pro is not available on this date. Please pick another day.';
  END IF;

  IF EXISTS (SELECT 1 FROM provider_availability WHERE provider_id = p_provider) THEN
    SELECT * INTO av FROM provider_availability
     WHERE provider_id = p_provider AND day_of_week = extract(dow FROM local_start)::int;
    IF NOT FOUND OR NOT av.is_available THEN
      RETURN 'The pro does not work on this day. Please pick another day.';
    END IF;
    IF local_start::time < av.start_time OR local_end::time > av.end_time
       OR local_end::date > local_start::date THEN
      RETURN format('Please choose a time within the pro''s working hours (%s – %s).',
                    to_char(av.start_time, 'HH24:MI'), to_char(av.end_time, 'HH24:MI'));
    END IF;
  END IF;

  IF EXISTS (
    SELECT 1 FROM bookings b
     WHERE b.provider_id = p_provider
       AND b.status IN ('pending', 'confirmed')
       AND b.id IS DISTINCT FROM p_ignore_booking
       AND b.booking_time < p_start + make_interval(mins => p_minutes + buf)
       AND b.booking_time + make_interval(mins => public._booking_minutes(b) + buf) > p_start
  ) THEN
    RETURN 'The pro already has a booking around that time. Please choose another slot.';
  END IF;

  RETURN NULL;
END;
$function$;
CREATE OR REPLACE FUNCTION public.create_manual_booking(p_service uuid, p_time timestamp with time zone, p_name text, p_phone text DEFAULT NULL::text, p_tier uuid DEFAULT NULL::uuid, p_price numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text, p_client uuid DEFAULT NULL::uuid, p_paid boolean DEFAULT false, p_address text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  uid uuid := auth.uid();
  svc services;
  mins int;
  buf int;
  done boolean := p_time <= now();
  b bookings;
BEGIN
  IF uid IS NULL OR NOT EXISTS (SELECT 1 FROM provider_profiles WHERE provider_id = uid) THEN
    RAISE EXCEPTION 'Only beauty pros can add bookings';
  END IF;
  SELECT * INTO svc FROM services WHERE id = p_service AND provider_id = uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pick one of your services'; END IF;
  IF p_tier IS NOT NULL AND NOT EXISTS (SELECT 1 FROM service_tiers WHERE id = p_tier AND service_id = p_service) THEN
    RAISE EXCEPTION 'Option not available';
  END IF;
  IF p_client IS NULL AND length(trim(coalesce(p_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Enter the client''s name';
  END IF;
  IF p_client IS NOT NULL AND NOT EXISTS (SELECT 1 FROM bookings WHERE client_id = p_client AND provider_id = uid) THEN
    RAISE EXCEPTION 'Client not found';
  END IF;
  IF p_price IS NOT NULL AND (p_price < 0 OR p_price > 10000) THEN RAISE EXCEPTION 'Check the price'; END IF;
  IF p_time < now() - interval '60 days' OR p_time > now() + interval '365 days' THEN
    RAISE EXCEPTION 'Pick a date within the last 60 days or the next year';
  END IF;

  mins := coalesce((SELECT duration_minutes FROM service_tiers WHERE id = p_tier), svc.duration_minutes, 60);
  buf := coalesce((SELECT buffer_minutes FROM provider_profiles WHERE provider_id = uid), 0);
  IF NOT done AND EXISTS (
    SELECT 1 FROM bookings x
     WHERE x.provider_id = uid AND x.status IN ('pending', 'confirmed')
       AND x.booking_time < p_time + make_interval(mins => mins + buf)
       AND x.booking_time + make_interval(mins => public._booking_minutes(x) + buf) > p_time) THEN
    RAISE EXCEPTION 'You already have a booking around that time';
  END IF;

  PERFORM public._bypass();
  INSERT INTO bookings(client_id, provider_id, service_id, tier_id, booking_time, address, status,
                       client_note, source, walkin_name, walkin_phone, agreed_price, negotiation_status,
                       payment_status, payment_method, service_completed_at, total_price)
  VALUES (p_client, uid, p_service, p_tier, p_time, coalesce(nullif(trim(p_address), ''), 'At the salon'),
          CASE WHEN done THEN 'completed' ELSE 'confirmed' END,
          nullif(trim(coalesce(p_note, '')), ''), 'manual',
          CASE WHEN p_client IS NULL THEN initcap(trim(p_name)) END,
          public._norm_phone(p_phone), p_price, CASE WHEN p_price IS NULL THEN 'none' ELSE 'agreed' END,
          CASE WHEN p_paid THEN 'paid' ELSE 'unpaid' END, 'cash',
          CASE WHEN done THEN p_time END, 0)
  RETURNING * INTO b;
  UPDATE bookings SET total_price = public._booking_total(b), deposit_amount = 0 WHERE id = b.id;
  RETURN b.id;
END $function$;
CREATE OR REPLACE FUNCTION public.mark_no_show(p_booking_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_prov boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status <> 'confirmed' THEN RAISE EXCEPTION 'Only confirmed bookings can be marked as a no-show'; END IF;
  IF b.booking_time > now() THEN RAISE EXCEPTION 'You can only report a no-show after the booking time'; END IF;
  by_prov := auth.uid() = b.provider_id;

  IF by_prov THEN
    SELECT * INTO pol FROM cancellation_policies WHERE provider_id = b.provider_id;
    IF FOUND THEN fee := round(b.total_price * pol.no_show_fee_percent / 100.0, 2); END IF;
  END IF;

  PERFORM public._bypass();
  UPDATE bookings SET status = 'cancelled', cancelled_at = now(),
         cancelled_by = CASE WHEN by_prov THEN 'client' ELSE 'provider' END,
         no_show_by = CASE WHEN by_prov THEN 'client' ELSE 'provider' END,
         no_show_at = now(), cancellation_fee = fee,
         cancel_reason = CASE WHEN by_prov THEN 'Client did not show up' ELSE 'Pro did not show up' END
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_prov THEN b.client_id ELSE b.provider_id END, 'booking', 'Marked as No-Show',
          CASE WHEN by_prov THEN 'Your pro reported that you missed your appointment.'
               ELSE 'The client reported that you did not arrive for the appointment.' END
          || CASE WHEN fee > 0 THEN format(' No-show fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$function$;
CREATE OR REPLACE FUNCTION public.reschedule_booking(p_booking_id uuid, p_new_time timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; msg text; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'Only upcoming bookings can be moved';
  END IF;
  by_client := auth.uid() = b.client_id;
  msg := public.check_slot(b.provider_id, p_new_time, public._booking_minutes(b), b.id);
  IF msg IS NOT NULL THEN RAISE EXCEPTION '%', msg; END IF;

  PERFORM public._bypass();
  UPDATE bookings SET booking_time = p_new_time, reminder_sent = false, rescheduled_at = now(),
         status = CASE WHEN by_client THEN 'pending' ELSE status END
   WHERE id = b.id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_client THEN b.provider_id ELSE b.client_id END, 'booking', 'Booking Moved',
          CASE WHEN by_client THEN 'Your client moved their booking to '
               ELSE 'Your pro moved your booking to ' END
          || to_char(p_new_time AT TIME ZONE 'Africa/Harare', 'Dy DD Mon, HH24:MI')
          || CASE WHEN by_client THEN '. Please confirm the new time.' ELSE '.' END,
          b.id::text);
END;
$function$;
