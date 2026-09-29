-- ============================================================
-- BeauTap Phase 1: real availability, tiers, reschedule, deposits,
-- free stylist tier, featured placement, guest booking limits.
-- Clients no longer pay an activation fee; price haggling retired.
-- ============================================================

BEGIN;

-- ---------- columns & tables ----------
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS min_notice_hours int NOT NULL DEFAULT 2
  CHECK (min_notice_hours BETWEEN 0 AND 168);
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS max_advance_days int NOT NULL DEFAULT 60
  CHECK (max_advance_days BETWEEN 1 AND 365);
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS deposit_percent int NOT NULL DEFAULT 0
  CHECK (deposit_percent BETWEEN 0 AND 100);
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS featured_until timestamptz;

CREATE TABLE IF NOT EXISTS service_tiers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL,
  price numeric(10,2) NOT NULL CHECK (price > 0),
  duration_minutes int NOT NULL DEFAULT 60 CHECK (duration_minutes > 0),
  sort_order int NOT NULL DEFAULT 0,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now()
);
ALTER TABLE service_tiers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Anyone can view tiers" ON service_tiers;
CREATE POLICY "Anyone can view tiers" ON service_tiers FOR SELECT USING (true);
DROP POLICY IF EXISTS "Providers manage own tiers" ON service_tiers;
CREATE POLICY "Providers manage own tiers" ON service_tiers FOR ALL
  USING (auth.uid() = provider_id)
  WITH CHECK (auth.uid() = provider_id AND EXISTS (
    SELECT 1 FROM services WHERE id = service_id AND provider_id = auth.uid()));
CREATE INDEX IF NOT EXISTS idx_service_tiers_service ON service_tiers(service_id);

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS tier_id uuid REFERENCES service_tiers(id) ON DELETE SET NULL;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS ref text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS deposit_amount numeric(10,2) NOT NULL DEFAULT 0;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS deposit_paid boolean NOT NULL DEFAULT false;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS rescheduled_at timestamptz;
UPDATE bookings SET ref = 'BT' || upper(substr(replace(id::text, '-', ''), 1, 6)) WHERE ref IS NULL;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_purpose_check;
ALTER TABLE payments ADD CONSTRAINT payments_purpose_check
  CHECK (purpose IN ('booking', 'activation', 'subscription', 'deposit', 'featured'));

-- Clients no longer pay to activate
UPDATE profiles SET is_activated = true WHERE user_type = 'client' AND NOT is_activated;

-- ---------- plans ----------
CREATE OR REPLACE FUNCTION public.free_bookings_used(p_provider uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM bookings
   WHERE provider_id = p_provider
     AND created_at >= (date_trunc('month', now() AT TIME ZONE 'Africa/Harare') AT TIME ZONE 'Africa/Harare')
     AND NOT (status = 'cancelled' AND cancelled_by = 'client');
$$;

CREATE OR REPLACE FUNCTION public.provider_can_accept(p_provider uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT public.provider_is_active(p_provider) OR public.free_bookings_used(p_provider) < 5;
$$;

CREATE OR REPLACE FUNCTION public.my_plan() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'plan', CASE WHEN public.provider_is_active(auth.uid()) THEN 'pro' ELSE 'free' END,
    'free_used', public.free_bookings_used(auth.uid()),
    'free_limit', 5,
    'pro_until', (SELECT end_date FROM subscriptions WHERE provider_id = auth.uid() AND status = 'active'),
    'featured_until', (SELECT featured_until FROM provider_profiles WHERE provider_id = auth.uid())
  );
$$;

CREATE OR REPLACE FUNCTION public._deposit_for(p_provider uuid, p_total numeric) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT round(coalesce(p_total, 0) * coalesce(
    (SELECT deposit_percent FROM provider_profiles WHERE provider_id = p_provider), 0) / 100.0, 2);
$$;

-- ---------- booking reference ----------
CREATE OR REPLACE FUNCTION public.bookings_set_ref() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.ref IS NULL THEN
    NEW.ref := 'BT' || upper(substr(replace(NEW.id::text, '-', ''), 1, 6));
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_bookings_set_ref ON bookings;
CREATE TRIGGER trg_bookings_set_ref BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_set_ref();

-- ---------- updated guards & pricing ----------
CREATE OR REPLACE FUNCTION public.provider_profiles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.average_rating := 0;
    NEW.total_reviews := 0;
    NEW.featured_until := NULL;
    RETURN NEW;
  END IF;
  NEW.average_rating := OLD.average_rating;
  NEW.total_reviews := OLD.total_reviews;
  NEW.featured_until := OLD.featured_until;
  -- Providers may hide themselves, but only a paid subscription unhides them
  IF OLD.is_hidden AND NOT NEW.is_hidden THEN NEW.is_hidden := true; END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public._booking_base_price(b bookings) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    b.agreed_price,
    CASE WHEN b.negotiation_status = 'client_offered' THEN b.client_offered_price END,
    (SELECT price FROM service_tiers WHERE id = b.tier_id AND service_id = b.service_id),
    (SELECT package_price FROM service_packages WHERE id = b.package_id AND provider_id = b.provider_id),
    (SELECT price FROM services WHERE id = b.service_id),
    0);
$$;

CREATE OR REPLACE FUNCTION public._booking_minutes(b bookings) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
           (SELECT sum(s.duration_minutes)::int FROM package_services ps JOIN services s ON s.id = ps.service_id
             WHERE ps.package_id = b.package_id),
           (SELECT duration_minutes FROM service_tiers WHERE id = b.tier_id AND service_id = b.service_id),
           (SELECT duration_minutes FROM services WHERE id = b.service_id),
           60)
       + coalesce((SELECT sum(addon_duration)::int FROM booking_addons WHERE booking_id = b.id), 0);
$$;

CREATE OR REPLACE FUNCTION public.check_slot(p_provider uuid, p_start timestamptz, p_minutes int,
                                             p_ignore_booking uuid DEFAULT NULL)
RETURNS text
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  local_start timestamp := p_start AT TIME ZONE 'Africa/Harare';
  local_end   timestamp := (p_start + make_interval(mins => p_minutes)) AT TIME ZONE 'Africa/Harare';
  av provider_availability;
  buf int := coalesce((SELECT buffer_minutes FROM provider_profiles WHERE provider_id = p_provider), 0);
  notice int := coalesce((SELECT min_notice_hours FROM provider_profiles WHERE provider_id = p_provider), 2);
  advance int := coalesce((SELECT max_advance_days FROM provider_profiles WHERE provider_id = p_provider), 60);
BEGIN
  IF p_start < now() + make_interval(hours => notice) THEN
    RETURN format('This stylist needs at least %s hour%s notice.', notice, CASE WHEN notice = 1 THEN '' ELSE 's' END);
  END IF;
  IF p_start > now() + make_interval(days => advance) THEN
    RETURN format('This stylist takes bookings up to %s days ahead.', advance);
  END IF;

  IF EXISTS (SELECT 1 FROM provider_blocked_dates
              WHERE provider_id = p_provider AND blocked_date = local_start::date) THEN
    RETURN 'The stylist is not available on this date. Please pick another day.';
  END IF;

  IF EXISTS (SELECT 1 FROM provider_availability WHERE provider_id = p_provider) THEN
    SELECT * INTO av FROM provider_availability
     WHERE provider_id = p_provider AND day_of_week = extract(dow FROM local_start)::int;
    IF NOT FOUND OR NOT av.is_available THEN
      RETURN 'The stylist does not work on this day. Please pick another day.';
    END IF;
    IF local_start::time < av.start_time OR local_end::time > av.end_time
       OR local_end::date > local_start::date THEN
      RETURN format('Please choose a time within the stylist''s working hours (%s – %s).',
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
    RETURN 'The stylist already has a booking around that time. Please choose another slot.';
  END IF;

  RETURN NULL;
END;
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

CREATE OR REPLACE FUNCTION public.booking_addons_retotal() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings;
BEGIN
  PERFORM public._bypass();
  UPDATE bookings SET addons_total = coalesce((
    SELECT sum(addon_price) FROM booking_addons WHERE booking_id = NEW.booking_id), 0)
   WHERE id = NEW.booking_id RETURNING * INTO b;
  UPDATE bookings SET total_price = public._booking_total(b),
         deposit_amount = CASE WHEN deposit_paid THEN deposit_amount
                               ELSE public._deposit_for(provider_id, public._booking_total(b)) END
   WHERE id = NEW.booking_id;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.quotes_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT public.provider_can_accept(auth.uid()) THEN
      RAISE EXCEPTION 'You have used this month''s free bookings. Upgrade to Pro to keep quoting.';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM service_requests WHERE id = NEW.request_id AND status = 'open') THEN
      RAISE EXCEPTION 'This request is no longer open';
    END IF;
    IF NEW.quoted_price IS NULL OR NEW.quoted_price <= 0 THEN RAISE EXCEPTION 'Invalid price'; END IF;
    NEW.status := 'pending';
  ELSE
    IF OLD.status <> 'pending' THEN RAISE EXCEPTION 'This quote can no longer be changed'; END IF;
    NEW.status := OLD.status;                 -- status changes go through accept_quote
    NEW.request_id := OLD.request_id;
    NEW.provider_id := OLD.provider_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_quote(p_quote_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q service_request_quotes; r service_requests; svc_id uuid; bk uuid; when_ts timestamptz;
BEGIN
  SELECT * INTO q FROM service_request_quotes WHERE id = p_quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  SELECT * INTO r FROM service_requests WHERE id = q.request_id FOR UPDATE;
  IF r.client_id <> auth.uid() THEN RAISE EXCEPTION 'Quote not found'; END IF;
  IF r.status <> 'open' OR q.status <> 'pending' THEN RAISE EXCEPTION 'This request is no longer open'; END IF;
  IF NOT public.provider_can_accept(q.provider_id) THEN
    RAISE EXCEPTION 'This stylist is not accepting bookings right now';
  END IF;

  SELECT id INTO svc_id FROM services
   WHERE provider_id = q.provider_id AND coalesce(is_active, true)
   ORDER BY (category_id IS NOT DISTINCT FROM r.category_id) DESC, created_at
   LIMIT 1;
  IF svc_id IS NULL THEN RAISE EXCEPTION 'This stylist has no active services'; END IF;

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
$$;

-- ---------- availability ----------
CREATE OR REPLACE FUNCTION public.available_slots(p_provider uuid, p_date date, p_minutes int)
RETURNS TABLE (slot text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  av provider_availability;
  day_start time := '08:00';
  day_end time := '18:00';
  t time;
  ts timestamptz;
BEGIN
  IF p_minutes IS NULL OR p_minutes <= 0 THEN p_minutes := 60; END IF;
  IF EXISTS (SELECT 1 FROM provider_availability WHERE provider_id = p_provider) THEN
    SELECT * INTO av FROM provider_availability
     WHERE provider_id = p_provider AND day_of_week = extract(dow FROM p_date)::int;
    IF NOT FOUND OR NOT av.is_available THEN RETURN; END IF;
    day_start := av.start_time;
    day_end := av.end_time;
  END IF;
  t := day_start;
  WHILE t + make_interval(mins => p_minutes) <= day_end AND t >= day_start LOOP
    ts := (p_date + t) AT TIME ZONE 'Africa/Harare';
    IF public.check_slot(p_provider, ts, p_minutes) IS NULL THEN
      slot := to_char(t, 'HH24:MI');
      RETURN NEXT;
    END IF;
    EXIT WHEN t > time '23:00';
    t := t + interval '30 minutes';
  END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.available_dates(p_provider uuid, p_from date, p_days int, p_minutes int)
RETURNS TABLE (day date, slots int)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE d date;
BEGIN
  FOR i IN 0 .. least(greatest(p_days, 1), 31) - 1 LOOP
    d := p_from + i;
    day := d;
    slots := (SELECT count(*) FROM public.available_slots(p_provider, d, p_minutes));
    RETURN NEXT;
  END LOOP;
END;
$$;

-- ---------- reschedule ----------
CREATE OR REPLACE FUNCTION public.reschedule_booking(p_booking_id uuid, p_new_time timestamptz)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings; msg text; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (b.client_id, b.provider_id) THEN
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
               ELSE 'Your stylist moved your booking to ' END
          || to_char(p_new_time AT TIME ZONE 'Africa/Harare', 'Dy DD Mon, HH24:MI')
          || CASE WHEN by_client THEN '. Please confirm the new time.' ELSE '.' END,
          b.id::text);
END;
$$;

-- ---------- permissions ----------
REVOKE ALL ON FUNCTION public.available_slots(uuid, date, int), public.available_dates(uuid, date, int, int),
  public.reschedule_booking(uuid, timestamptz), public.my_plan(), public.provider_can_accept(uuid),
  public.free_bookings_used(uuid), public._deposit_for(uuid, numeric) FROM public;
GRANT EXECUTE ON FUNCTION public.available_slots(uuid, date, int), public.available_dates(uuid, date, int, int)
  TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.reschedule_booking(uuid, timestamptz), public.my_plan(),
  public.provider_can_accept(uuid) TO authenticated;

COMMIT;
