-- Pros' street addresses were readable by anyone through provider_profiles.
-- Keep them in a table only the pro and admins can read. Clients still get
-- the address on their own studio booking, exactly as before.

CREATE TABLE IF NOT EXISTS public.provider_private (
  provider_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  address text CHECK (address IS NULL OR length(address) <= 200),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.provider_private ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.provider_private FROM anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.provider_private TO authenticated;

DROP POLICY IF EXISTS provider_private_own ON public.provider_private;
CREATE POLICY provider_private_own ON public.provider_private FOR ALL TO authenticated
  USING (provider_id = auth.uid() OR public.is_admin())
  WITH CHECK (provider_id = auth.uid() OR public.is_admin());

CREATE OR REPLACE FUNCTION public.provider_private_touch() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  NEW.address := left(nullif(trim(NEW.address), ''), 200);
  NEW.updated_at := now();
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_provider_private_touch ON public.provider_private;
CREATE TRIGGER trg_provider_private_touch BEFORE INSERT OR UPDATE ON public.provider_private
  FOR EACH ROW EXECUTE FUNCTION public.provider_private_touch();

-- Move existing addresses. The location sync trigger would stamp every pro as
-- "moved", so it's off for this one update.
INSERT INTO public.provider_private (provider_id, address)
SELECT pp.provider_id, pp.address
  FROM provider_profiles pp
  JOIN auth.users u ON u.id = pp.provider_id
 WHERE nullif(trim(pp.address), '') IS NOT NULL
ON CONFLICT (provider_id) DO UPDATE SET address = EXCLUDED.address;

ALTER TABLE provider_profiles DISABLE TRIGGER trg_provider_location_sync;
UPDATE provider_profiles SET address = NULL WHERE address IS NOT NULL;
ALTER TABLE provider_profiles ENABLE TRIGGER trg_provider_location_sync;

-- Older app versions still write provider_profiles.address. Divert those
-- writes into the private table so the public column always stays empty.
-- Named "zz" to run after trg_provider_location_sync, which compares addresses.
CREATE OR REPLACE FUNCTION public.provider_address_to_private() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF nullif(trim(NEW.address), '') IS NOT NULL THEN
    INSERT INTO provider_private (provider_id, address) VALUES (NEW.provider_id, NEW.address)
    ON CONFLICT (provider_id) DO UPDATE SET address = EXCLUDED.address;
  END IF;
  NEW.address := NULL;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_provider_zz_address_private ON provider_profiles;
CREATE TRIGGER trg_provider_zz_address_private BEFORE INSERT OR UPDATE ON provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.provider_address_to_private();

-- Studio bookings: bookings_guard now finds no public address and writes
-- "Area, City". The street address goes on the booking only once it's
-- confirmed, as the app promises pros ("after you confirm their booking").
-- Named "zz" to run after trg_bookings_guard.
CREATE OR REPLACE FUNCTION public.bookings_studio_address() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE a text;
BEGIN
  IF NOT coalesce(NEW.at_studio, false) OR NEW.status IS DISTINCT FROM 'confirmed' THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' AND OLD.status IS NOT DISTINCT FROM 'confirmed' THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' AND public.is_privileged() THEN RETURN NEW; END IF;
  SELECT address INTO a FROM provider_private WHERE provider_id = NEW.provider_id;
  IF a IS NOT NULL THEN NEW.address := a; END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bookings_zz_studio_address ON bookings;
CREATE TRIGGER trg_bookings_zz_studio_address BEFORE INSERT OR UPDATE OF status ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_studio_address();

-- Pending studio bookings made before this already carry the street address.
-- Swap it for "Area, City" until the pro confirms. Triggers are off so this
-- cleanup doesn't send booking notifications.
ALTER TABLE bookings DISABLE TRIGGER USER;
UPDATE bookings b
   SET address = coalesce((SELECT pp.area || ', ' || c.name
                             FROM provider_profiles pp JOIN cities c ON c.id = pp.city_id
                            WHERE pp.provider_id = b.provider_id),
                          'At the pro''s place')
 WHERE b.status = 'pending' AND b.at_studio
   AND b.address IN (SELECT address FROM provider_private WHERE provider_id = b.provider_id);
ALTER TABLE bookings ENABLE TRIGGER USER;
