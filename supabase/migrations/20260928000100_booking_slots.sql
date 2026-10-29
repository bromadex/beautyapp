-- ============================================================
-- BeauTap: server-side slot availability
-- Clients cannot read other people's bookings, so overlap checks
-- must run on the server. Checks working hours, blocked dates,
-- buffer time and overlapping bookings (times in Africa/Harare).
-- ============================================================

BEGIN;

CREATE OR REPLACE FUNCTION public._booking_minutes(b bookings) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(
           (SELECT sum(s.duration_minutes)::int FROM package_services ps JOIN services s ON s.id = ps.service_id
             WHERE ps.package_id = b.package_id),
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
BEGIN
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

REVOKE ALL ON FUNCTION public.check_slot(uuid, timestamptz, int, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.check_slot(uuid, timestamptz, int, uuid) TO authenticated;

-- Enforce on insert (add-ons are added after the booking row, so the
-- app checks the full duration first; this guards the base duration).
CREATE OR REPLACE FUNCTION public.bookings_slot_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE msg text;
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  msg := public.check_slot(NEW.provider_id, NEW.booking_time, public._booking_minutes(NEW), NEW.id);
  IF msg IS NOT NULL THEN RAISE EXCEPTION '%', msg; END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_bookings_slot_guard ON bookings;
CREATE TRIGGER trg_bookings_slot_guard BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_slot_guard();

COMMIT;
