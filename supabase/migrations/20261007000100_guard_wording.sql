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
      NEW.address := coalesce(nullif(trim(pp.address), ''), 'At the pro''s place');
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
$function$
;