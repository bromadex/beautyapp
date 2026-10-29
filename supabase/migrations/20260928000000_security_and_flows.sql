-- ============================================================
-- BeauTap: security hardening + server-side business flows
--
-- Users could previously write money and trust fields directly
-- (payments, subscriptions, booking prices, activation, verification,
-- ratings). This migration makes those server-owned and adds RPCs
-- for the flows that legitimately change them.
--
-- "Privileged" = service role (edge functions), direct DB sessions
-- (SQL editor, cron, auth triggers), admins, or an RPC in this file
-- that has set the beautap.bypass flag for its transaction.
-- ============================================================

BEGIN;

-- ---------- helpers ----------
CREATE OR REPLACE FUNCTION public.is_admin() RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM public.admins WHERE user_id = auth.uid());
$$;

CREATE OR REPLACE FUNCTION public.is_privileged() RETURNS boolean
LANGUAGE sql STABLE SET search_path = public AS $$
  SELECT coalesce(current_setting('beautap.bypass', true), '') = 'on'
      OR coalesce(auth.role(), '') NOT IN ('authenticated', 'anon')
      OR public.is_admin();
$$;

CREATE OR REPLACE FUNCTION public._bypass() RETURNS void
LANGUAGE sql AS $$ SELECT set_config('beautap.bypass', 'on', true); $$;
REVOKE ALL ON FUNCTION public._bypass() FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.provider_is_active(p_provider uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.subscriptions
    WHERE provider_id = p_provider AND status = 'active' AND end_date >= current_date
  );
$$;

CREATE OR REPLACE FUNCTION public._haversine_km(lat1 double precision, lon1 double precision,
                                                lat2 double precision, lon2 double precision)
RETURNS double precision LANGUAGE sql IMMUTABLE AS $$
  SELECT 6371 * 2 * asin(sqrt(
    power(sin(radians(lat2 - lat1) / 2), 2) +
    cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lon2 - lon1) / 2), 2)));
$$;

-- ---------- new columns ----------
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_lat double precision;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_lng double precision;
ALTER TABLE bookings ALTER COLUMN payment_method SET DEFAULT 'cash';

-- ---------- profiles: trust fields are server-owned ----------
CREATE OR REPLACE FUNCTION public.profiles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.is_verified := false;
    NEW.is_business_verified := false;
    NEW.is_banned := false;
    NEW.is_activated := (NEW.user_type = 'provider');
    RETURN NEW;
  END IF;

  NEW.is_verified := OLD.is_verified;
  NEW.is_business_verified := OLD.is_business_verified;
  NEW.is_banned := OLD.is_banned;

  -- Account type may only change on a new account with no bookings
  -- (the Google sign-up flow sets it right after the profile is created).
  IF NEW.user_type IS DISTINCT FROM OLD.user_type AND (
       OLD.created_at < now() - interval '1 day'
       OR EXISTS (SELECT 1 FROM bookings WHERE client_id = OLD.id OR provider_id = OLD.id)
     ) THEN
    NEW.user_type := OLD.user_type;
  END IF;

  IF NEW.user_type = 'provider' THEN
    NEW.is_activated := true;
  ELSIF OLD.user_type = 'provider' THEN
    NEW.is_activated := false;          -- switching back to client must pay
  ELSE
    NEW.is_activated := OLD.is_activated;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_profiles_guard ON profiles;
CREATE TRIGGER trg_profiles_guard BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_guard();

-- ---------- provider_profiles: ratings are server-owned ----------
CREATE OR REPLACE FUNCTION public.provider_profiles_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.average_rating := 0;
    NEW.total_reviews := 0;
    RETURN NEW;
  END IF;
  NEW.average_rating := OLD.average_rating;
  NEW.total_reviews := OLD.total_reviews;
  -- Providers may hide themselves, but only a paid subscription unhides them
  IF OLD.is_hidden AND NOT NEW.is_hidden THEN NEW.is_hidden := true; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_provider_profiles_guard ON provider_profiles;
CREATE TRIGGER trg_provider_profiles_guard BEFORE INSERT OR UPDATE ON provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.provider_profiles_guard();

CREATE OR REPLACE FUNCTION public.update_provider_rating() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._bypass();
  UPDATE provider_profiles SET
    average_rating = (SELECT round(avg(rating)::numeric, 2) FROM reviews WHERE provider_id = NEW.provider_id),
    total_reviews  = (SELECT count(*) FROM reviews WHERE provider_id = NEW.provider_id)
  WHERE provider_id = NEW.provider_id;
  RETURN NEW;
END;
$$;

-- ---------- subscriptions & payments: only the server writes ----------
DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname, tablename FROM pg_policies
           WHERE schemaname = 'public'
             AND ((tablename = 'subscriptions' AND cmd IN ('INSERT', 'UPDATE') AND coalesce(qual, with_check) NOT LIKE '%admins%')
               OR (tablename = 'payments'      AND cmd IN ('INSERT', 'UPDATE') AND coalesce(qual, with_check) NOT LIKE '%admins%'))
  LOOP
    EXECUTE format('DROP POLICY %I ON public.%I', r.policyname, r.tablename);
  END LOOP;
END $$;

CREATE OR REPLACE FUNCTION public.cancel_my_subscription() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._bypass();
  UPDATE subscriptions SET status = 'cancelled' WHERE provider_id = auth.uid();
  UPDATE provider_profiles SET is_hidden = true WHERE provider_id = auth.uid();
END;
$$;

-- ---------- promotions ----------
CREATE OR REPLACE FUNCTION public.check_promo(p_provider uuid, p_code text, p_amount numeric)
RETURNS TABLE (promo_id uuid, discount numeric, error text)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE p promotions;
BEGIN
  SELECT * INTO p FROM promotions
   WHERE provider_id = p_provider AND upper(code) = upper(trim(p_code)) AND is_active
   LIMIT 1;
  IF NOT FOUND THEN RETURN QUERY SELECT NULL::uuid, 0::numeric, 'Invalid promo code'; RETURN; END IF;
  IF p.valid_from IS NOT NULL AND p.valid_from > now() THEN
    RETURN QUERY SELECT NULL::uuid, 0::numeric, 'This promo code is not active yet'; RETURN; END IF;
  IF p.valid_until IS NOT NULL AND p.valid_until < now() THEN
    RETURN QUERY SELECT NULL::uuid, 0::numeric, 'This promo code has expired'; RETURN; END IF;
  IF p.max_uses IS NOT NULL AND coalesce(p.used_count, 0) >= p.max_uses THEN
    RETURN QUERY SELECT NULL::uuid, 0::numeric, 'This promo code has reached its limit'; RETURN; END IF;
  IF p_amount < coalesce(p.min_order_amount, 0) THEN
    RETURN QUERY SELECT NULL::uuid, 0::numeric,
      format('Min order $%s required', round(p.min_order_amount)); RETURN; END IF;
  RETURN QUERY SELECT p.id,
    round(least(p_amount, CASE WHEN p.discount_type = 'percentage'
                               THEN p_amount * p.discount_value / 100
                               ELSE p.discount_value END), 2),
    NULL::text;
END;
$$;

-- ---------- bookings ----------
CREATE OR REPLACE FUNCTION public._booking_base_price(b bookings) RETURNS numeric
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
    b.agreed_price,
    CASE WHEN b.negotiation_status = 'client_offered' THEN b.client_offered_price END,
    (SELECT package_price FROM service_packages WHERE id = b.package_id AND provider_id = b.provider_id),
    (SELECT price FROM services WHERE id = b.service_id),
    0);
$$;

CREATE OR REPLACE FUNCTION public._booking_total(b bookings) RETURNS numeric
LANGUAGE sql STABLE AS $$
  SELECT round(greatest(public._booking_base_price(b) - coalesce(b.discount_amount, 0), 0)
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
    IF NOT coalesce((SELECT is_activated FROM profiles WHERE id = uid), true) THEN
      RAISE EXCEPTION 'ACTIVATION_REQUIRED';
    END IF;
    IF NOT public.provider_is_active(NEW.provider_id) THEN
      RAISE EXCEPTION 'This stylist is not accepting bookings yet';
    END IF;
    SELECT * INTO svc FROM services WHERE id = NEW.service_id AND provider_id = NEW.provider_id;
    IF NOT FOUND OR NOT coalesce(svc.is_active, true) THEN
      RAISE EXCEPTION 'Service not available';
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

    IF NEW.client_offered_price IS NOT NULL THEN
      IF NEW.client_offered_price <= 0 THEN RAISE EXCEPTION 'Invalid offer'; END IF;
      NEW.negotiation_status := 'client_offered';
      NEW.negotiation_rounds := 1;
    ELSE
      NEW.negotiation_status := 'none';
      NEW.negotiation_rounds := 0;
      NEW.offer_expires_at := NULL;
    END IF;

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
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bookings_guard ON bookings;
CREATE TRIGGER trg_bookings_guard BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_guard();

-- booking_addons: copy name/price from the provider's add-on, then re-total
CREATE OR REPLACE FUNCTION public.booking_addons_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a service_addons; b bookings;
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  SELECT * INTO b FROM bookings WHERE id = NEW.booking_id;
  IF b.client_id IS DISTINCT FROM auth.uid() OR b.status <> 'pending' THEN
    RAISE EXCEPTION 'Not allowed';
  END IF;
  SELECT * INTO a FROM service_addons
   WHERE id = NEW.addon_id AND service_id = b.service_id AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'Add-on not available'; END IF;
  NEW.addon_name := a.name;
  NEW.addon_price := a.price;
  NEW.addon_duration := a.duration_minutes;
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
  UPDATE bookings SET total_price = public._booking_total(b) WHERE id = NEW.booking_id;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_booking_addons_guard ON booking_addons;
CREATE TRIGGER trg_booking_addons_guard BEFORE INSERT ON booking_addons
  FOR EACH ROW EXECUTE FUNCTION public.booking_addons_guard();
DROP TRIGGER IF EXISTS trg_booking_addons_retotal ON booking_addons;
CREATE TRIGGER trg_booking_addons_retotal AFTER INSERT ON booking_addons
  FOR EACH ROW EXECUTE FUNCTION public.booking_addons_retotal();

-- Cancel (either party) with the provider's cancellation policy applied
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid, p_reason text DEFAULT NULL)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (b.client_id, b.provider_id) THEN
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
          CASE WHEN by_client THEN 'The client cancelled their booking.' ELSE 'Your stylist cancelled the booking.' END
          || coalesce(' Reason: ' || nullif(trim(p_reason), ''), '')
          || CASE WHEN fee > 0 THEN format(' Late cancellation fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$$;

-- Mark a no-show after the booking time has passed
CREATE OR REPLACE FUNCTION public.mark_no_show(p_booking_id uuid)
RETURNS numeric
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_prov boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR auth.uid() NOT IN (b.client_id, b.provider_id) THEN
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
         cancel_reason = CASE WHEN by_prov THEN 'Client did not show up' ELSE 'Stylist did not show up' END
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_prov THEN b.client_id ELSE b.provider_id END, 'booking', 'Marked as No-Show',
          CASE WHEN by_prov THEN 'Your stylist reported that you missed your appointment.'
               ELSE 'The client reported that you did not arrive for the appointment.' END
          || CASE WHEN fee > 0 THEN format(' No-show fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$$;

-- Cash payments
CREATE OR REPLACE FUNCTION public.choose_cash_payment(p_booking_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR b.client_id <> auth.uid() THEN RAISE EXCEPTION 'Booking not found'; END IF;
  IF b.payment_status = 'paid' THEN RAISE EXCEPTION 'This booking is already paid'; END IF;
  PERFORM public._bypass();
  IF NOT EXISTS (SELECT 1 FROM payments WHERE booking_id = b.id AND method = 'cash_on_delivery' AND status = 'pending') THEN
    INSERT INTO payments (booking_id, client_id, provider_id, amount, method, status, transaction_ref, gateway, purpose)
    VALUES (b.id, b.client_id, b.provider_id, b.total_price, 'cash_on_delivery', 'pending',
            'CASH-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12), 'cash', 'booking');
  END IF;
  UPDATE bookings SET payment_status = 'cod_pending', payment_method = 'cash' WHERE id = b.id;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (b.provider_id, 'payment', 'Cash Payment',
          format('Client will pay $%s in cash.', b.total_price), b.id::text);
END;
$$;

CREATE OR REPLACE FUNCTION public.confirm_cash_received(p_booking_id uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b bookings;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR b.provider_id <> auth.uid() THEN RAISE EXCEPTION 'Booking not found'; END IF;
  PERFORM public._bypass();
  IF EXISTS (SELECT 1 FROM payments WHERE booking_id = b.id AND method = 'cash_on_delivery' AND status = 'pending') THEN
    UPDATE payments SET status = 'paid', paid_at = now()
     WHERE booking_id = b.id AND method = 'cash_on_delivery' AND status = 'pending';
  ELSIF b.payment_status <> 'paid' THEN
    INSERT INTO payments (booking_id, client_id, provider_id, amount, method, status, transaction_ref, gateway, purpose, paid_at)
    VALUES (b.id, b.client_id, b.provider_id, b.total_price, 'cash_on_delivery', 'paid',
            'CASH-' || substr(replace(gen_random_uuid()::text, '-', ''), 1, 12), 'cash', 'booking', now());
  END IF;
  UPDATE bookings SET payment_status = 'paid',
         status = CASE WHEN status = 'confirmed' THEN 'completed' ELSE status END,
         service_completed_at = coalesce(service_completed_at, CASE WHEN status = 'confirmed' THEN now() END)
   WHERE id = b.id;
END;
$$;

-- ---------- notifications: only to people you have a booking/quote with ----------
CREATE OR REPLACE FUNCTION public.can_notify(p_target uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT p_target = auth.uid()
      OR public.is_admin()
      OR EXISTS (SELECT 1 FROM bookings
                  WHERE (client_id = auth.uid() AND provider_id = p_target)
                     OR (provider_id = auth.uid() AND client_id = p_target))
      OR EXISTS (SELECT 1 FROM service_request_quotes q JOIN service_requests r ON r.id = q.request_id
                  WHERE (q.provider_id = auth.uid() AND r.client_id = p_target)
                     OR (r.client_id = auth.uid() AND q.provider_id = p_target));
$$;

DO $$
DECLARE r record;
BEGIN
  FOR r IN SELECT policyname FROM pg_policies
           WHERE schemaname = 'public' AND tablename = 'notifications' AND cmd = 'INSERT'
  LOOP
    EXECUTE format('DROP POLICY %I ON public.notifications', r.policyname);
  END LOOP;
END $$;
CREATE POLICY "Notify related users" ON notifications FOR INSERT
  WITH CHECK (auth.role() = 'authenticated' AND public.can_notify(user_id));

-- ---------- review replies ----------
DROP POLICY IF EXISTS "Providers reply to own reviews" ON reviews;
CREATE POLICY "Providers reply to own reviews" ON reviews FOR UPDATE
  USING (auth.uid() = provider_id) WITH CHECK (auth.uid() = provider_id);

CREATE OR REPLACE FUNCTION public.reviews_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.rating IS DISTINCT FROM OLD.rating OR NEW.comment IS DISTINCT FROM OLD.comment
       OR NEW.client_id IS DISTINCT FROM OLD.client_id OR NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.booking_id IS DISTINCT FROM OLD.booking_id
       OR NEW.after_service_image_url IS DISTINCT FROM OLD.after_service_image_url THEN
      RAISE EXCEPTION 'Only the reply can be changed';
    END IF;
    NEW.provider_reply_at := now();
  ELSE
    NEW.provider_reply := NULL;
    NEW.provider_reply_at := NULL;
    IF NEW.provider_id IS DISTINCT FROM (SELECT provider_id FROM bookings WHERE id = NEW.booking_id) THEN
      RAISE EXCEPTION 'Review does not match booking';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_reviews_guard ON reviews;
CREATE TRIGGER trg_reviews_guard BEFORE INSERT OR UPDATE ON reviews
  FOR EACH ROW EXECUTE FUNCTION public.reviews_guard();

-- ---------- service request marketplace ----------
CREATE OR REPLACE FUNCTION public.i_quoted_on(p_request uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM service_request_quotes WHERE request_id = p_request AND provider_id = auth.uid());
$$;

DROP POLICY IF EXISTS "Anyone can view open requests" ON service_requests;
CREATE POLICY "Anyone can view open requests" ON service_requests FOR SELECT USING (
  status = 'open' OR client_id = auth.uid() OR public.i_quoted_on(id)
);

CREATE OR REPLACE FUNCTION public.quotes_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    IF NOT public.provider_is_active(auth.uid()) THEN
      RAISE EXCEPTION 'Activate your subscription to send quotes';
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
DROP TRIGGER IF EXISTS trg_quotes_guard ON service_request_quotes;
CREATE TRIGGER trg_quotes_guard BEFORE INSERT OR UPDATE ON service_request_quotes
  FOR EACH ROW EXECUTE FUNCTION public.quotes_guard();

CREATE OR REPLACE FUNCTION public.accept_quote(p_quote_id uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE q service_request_quotes; r service_requests; svc_id uuid; bk uuid; when_ts timestamptz;
BEGIN
  SELECT * INTO q FROM service_request_quotes WHERE id = p_quote_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Quote not found'; END IF;
  SELECT * INTO r FROM service_requests WHERE id = q.request_id FOR UPDATE;
  IF r.client_id <> auth.uid() THEN RAISE EXCEPTION 'Quote not found'; END IF;
  IF r.status <> 'open' OR q.status <> 'pending' THEN RAISE EXCEPTION 'This request is no longer open'; END IF;
  IF NOT coalesce((SELECT is_activated FROM profiles WHERE id = auth.uid()), true) THEN
    RAISE EXCEPTION 'ACTIVATION_REQUIRED';
  END IF;
  IF NOT public.provider_is_active(q.provider_id) THEN
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

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (q.provider_id, 'booking', 'Quote Accepted!',
          format('Your $%s quote for "%s" was accepted. Please confirm the booking.', q.quoted_price, r.title),
          bk::text);
  RETURN bk;
END;
$$;

-- ---------- business verification ----------
CREATE OR REPLACE FUNCTION public.review_business_verification(p_id uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE v business_verifications;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Not authorized'; END IF;
  UPDATE business_verifications SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         admin_notes = p_note, reviewed_at = now(), reviewed_by = auth.uid()
   WHERE id = p_id RETURNING * INTO v;
  PERFORM public._bypass();
  UPDATE profiles SET is_business_verified = p_approve WHERE id = v.provider_id;
  INSERT INTO notifications (user_id, type, title, body)
  VALUES (v.provider_id, 'verification',
          CASE WHEN p_approve THEN 'Business Verified' ELSE 'Business Verification Rejected' END,
          CASE WHEN p_approve THEN 'Your business is now verified on BeauTap.'
               ELSE 'Your business verification was not approved.' || coalesce(' ' || p_note, '') END);
END;
$$;

CREATE OR REPLACE FUNCTION public.business_verifications_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  NEW.status := 'pending';
  NEW.admin_notes := NULL; NEW.reviewed_at := NULL; NEW.reviewed_by := NULL;
  NEW.submitted_at := now();
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_business_verifications_guard ON business_verifications;
CREATE TRIGGER trg_business_verifications_guard BEFORE INSERT OR UPDATE ON business_verifications
  FOR EACH ROW EXECUTE FUNCTION public.business_verifications_guard();

-- Providers resubmit after a rejection
DROP POLICY IF EXISTS "Providers update own pending verification" ON business_verifications;
CREATE POLICY "Providers update own pending verification" ON business_verifications FOR UPDATE
  USING (auth.uid() = provider_id AND status IN ('pending', 'rejected'))
  WITH CHECK (auth.uid() = provider_id AND status = 'pending');

-- ---------- disputes: admins resolve ----------
CREATE OR REPLACE FUNCTION public.disputes_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF NOT EXISTS (SELECT 1 FROM bookings WHERE id = NEW.booking_id
                  AND auth.uid() IN (client_id, provider_id)) THEN
    RAISE EXCEPTION 'You can only report your own bookings';
  END IF;
  NEW.status := 'open';
  NEW.admin_notes := NULL; NEW.resolution := NULL; NEW.resolved_by := NULL; NEW.resolved_at := NULL;
  RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS trg_disputes_guard ON disputes;
CREATE TRIGGER trg_disputes_guard BEFORE INSERT ON disputes
  FOR EACH ROW EXECUTE FUNCTION public.disputes_guard();

-- ---------- RPC permissions ----------
REVOKE ALL ON FUNCTION public.cancel_my_subscription(), public.cancel_booking(uuid, text),
  public.mark_no_show(uuid), public.choose_cash_payment(uuid), public.confirm_cash_received(uuid),
  public.accept_quote(uuid), public.review_business_verification(uuid, boolean, text),
  public.check_promo(uuid, text, numeric) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.cancel_my_subscription(), public.cancel_booking(uuid, text),
  public.mark_no_show(uuid), public.choose_cash_payment(uuid), public.confirm_cash_received(uuid),
  public.accept_quote(uuid), public.review_business_verification(uuid, boolean, text),
  public.check_promo(uuid, text, numeric) TO authenticated;

COMMIT;
