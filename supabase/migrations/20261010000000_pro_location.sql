-- Every pro must say where they work (city + area) before clients can find
-- or book them. They can change it any time, e.g. after moving.

ALTER TABLE provider_profiles
  ADD COLUMN IF NOT EXISTS area text,
  ADD COLUMN IF NOT EXISTS location_updated_at timestamptz;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_area_len;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_area_len CHECK (area IS NULL OR length(area) <= 80);

CREATE OR REPLACE FUNCTION public.provider_has_location(p_provider uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT EXISTS (SELECT 1 FROM provider_profiles
                  WHERE provider_id = p_provider AND city_id IS NOT NULL
                    AND nullif(trim(area), '') IS NOT NULL);
$$;
GRANT EXECUTE ON FUNCTION public.provider_has_location(uuid) TO anon, authenticated;

-- Keep the pin and the "Area, City" text in step with the chosen city.
CREATE OR REPLACE FUNCTION public.provider_location_sync() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c cities;
BEGIN
  NEW.area := nullif(trim(NEW.area), '');
  IF NEW.city_id IS NOT NULL THEN
    SELECT * INTO c FROM cities WHERE id = NEW.city_id;
    -- New city without a fresh pin: use the city centre so distance works.
    IF TG_OP = 'INSERT' OR NEW.city_id IS DISTINCT FROM OLD.city_id THEN
      IF NEW.latitude IS NULL OR (TG_OP = 'UPDATE' AND NEW.latitude IS NOT DISTINCT FROM OLD.latitude
                                   AND NEW.longitude IS NOT DISTINCT FROM OLD.longitude) THEN
        NEW.latitude := c.lat;
        NEW.longitude := c.lng;
      END IF;
    END IF;
  END IF;
  IF TG_OP = 'INSERT' OR NEW.city_id IS DISTINCT FROM OLD.city_id OR NEW.area IS DISTINCT FROM OLD.area
     OR NEW.address IS DISTINCT FROM OLD.address THEN
    NEW.location_updated_at := now();
    IF NEW.city_id IS NOT NULL AND NEW.area IS NOT NULL THEN
      UPDATE profiles SET location = NEW.area || ', ' || c.name WHERE id = NEW.provider_id;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_provider_location_sync ON provider_profiles;
CREATE TRIGGER trg_provider_location_sync BEFORE INSERT OR UPDATE ON provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.provider_location_sync();

-- No bookings until the pro has set where they work (walk-ins they add
-- themselves are fine).
CREATE OR REPLACE FUNCTION public.bookings_location_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() OR NEW.source = 'manual' THEN RETURN NEW; END IF;
  IF NOT public.provider_has_location(NEW.provider_id) THEN
    RAISE EXCEPTION 'This pro hasn''t set where they work yet, so they can''t take bookings. Please try another pro.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bookings_location_guard ON bookings;
CREATE TRIGGER trg_bookings_location_guard BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_location_guard();

-- Upcoming bookings at the pro's place, so the app can warn before a move.
CREATE OR REPLACE FUNCTION public.my_upcoming_studio_bookings() RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM bookings
   WHERE provider_id = auth.uid() AND at_studio AND status IN ('pending', 'confirmed')
     AND booking_time > now();
$$;
REVOKE ALL ON FUNCTION public.my_upcoming_studio_bookings() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_upcoming_studio_bookings() TO authenticated;

-- Tell pros who haven't set it yet.
INSERT INTO notifications (user_id, type, title, body)
SELECT pp.provider_id, 'location', 'Set where you work',
       'Clients can only find and book you once you add your city and area. It takes a minute.'
  FROM provider_profiles pp
 WHERE NOT public.provider_has_location(pp.provider_id);
