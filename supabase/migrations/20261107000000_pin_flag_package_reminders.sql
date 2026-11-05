-- 1. Pros who never set a map pin sit on their city's centre. Mark which
--    pins are real so the map can leave the others off (they stay in the
--    list) instead of stacking them all on the centre.
-- 2. Automatic package reminders: before a new month ("renews on 1 Dec")
--    and early in the month if it isn't paid yet.

ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS has_own_pin boolean NOT NULL DEFAULT false;

-- Backfill from the exact pins.
ALTER TABLE provider_profiles DISABLE TRIGGER trg_provider_location_sync;
ALTER TABLE provider_profiles DISABLE TRIGGER trg_provider_zzz_pin_private;
UPDATE provider_profiles pp
   SET has_own_pin = v.lat IS NOT NULL AND NOT EXISTS (
         SELECT 1 FROM cities c WHERE c.id = pp.city_id
            AND abs(c.lat::double precision - v.lat::double precision) < 0.0005
            AND abs(c.lng::double precision - v.lng::double precision) < 0.0005)
  FROM provider_private v
 WHERE v.provider_id = pp.provider_id;
ALTER TABLE provider_profiles ENABLE TRIGGER trg_provider_zzz_pin_private;
ALTER TABLE provider_profiles ENABLE TRIGGER trg_provider_location_sync;

CREATE OR REPLACE FUNCTION public.provider_pin_to_private() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.latitude IS NOT NULL AND NEW.longitude IS NOT NULL
     AND (TG_OP = 'INSERT' OR NEW.latitude IS DISTINCT FROM OLD.latitude
          OR NEW.longitude IS DISTINCT FROM OLD.longitude) THEN
    INSERT INTO provider_private (provider_id, lat, lng) VALUES (NEW.provider_id, NEW.latitude, NEW.longitude)
    ON CONFLICT (provider_id) DO UPDATE SET lat = EXCLUDED.lat, lng = EXCLUDED.lng;
    -- A pin exactly on the city centre is the default, not a real place.
    NEW.has_own_pin := NOT EXISTS (
      SELECT 1 FROM cities c WHERE c.id = NEW.city_id
         AND abs(c.lat::double precision - NEW.latitude) < 0.0005
         AND abs(c.lng::double precision - NEW.longitude) < 0.0005);
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.has_own_pin := OLD.has_own_pin;
  END IF;
  NEW.latitude := public._round_pin(NEW.latitude);
  NEW.longitude := public._round_pin(NEW.longitude);
  RETURN NEW;
END $$;

-- ---------------------------------------------------------------------
-- Package reminders
-- ---------------------------------------------------------------------
ALTER TABLE public.package_members ADD COLUMN IF NOT EXISTS renew_reminded_for date;
ALTER TABLE public.package_periods ADD COLUMN IF NOT EXISTS reminded_at timestamptz;

-- Called by send-reminders (service role) every 15 minutes. Writes the
-- in-app notifications, marks what it sent, and returns the rows to push.
CREATE OR REPLACE FUNCTION public.package_reminders()
RETURNS TABLE (user_id uuid, title text, body text, route text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
#variable_conflict use_column
DECLARE
  today date := (now() AT TIME ZONE 'Africa/Harare')::date;
  next_month date := (date_trunc('month', now() AT TIME ZONE 'Africa/Harare') + interval '1 month')::date;
  m record; r package_periods; t text; b text;
BEGIN
  -- From the 26th: "renews on 1 Dec", once per member per month.
  IF extract(day FROM today) >= 26 THEN
    FOR m IN SELECT pm.id, pm.client_id, p.name, p.price, pr.full_name
               FROM package_members pm
               JOIN monthly_packages p ON p.id = pm.package_id
               JOIN profiles pr ON pr.id = pm.provider_id
              WHERE pm.status = 'active' AND pm.renew_reminded_for IS DISTINCT FROM next_month LOOP
      UPDATE package_members SET renew_reminded_for = next_month WHERE id = m.id;
      t := m.name || ' renews on 1 ' || to_char(next_month, 'Mon');
      b := 'Send ' || split_part(coalesce(m.full_name, 'your pro'), ' ', 1) || ' $' || trim_scale(m.price)
           || ' from the 1st to unlock next month''s visits, or cancel any time before then in My packages.';
      INSERT INTO notifications (user_id, type, title, body, reference_id) VALUES (m.client_id, 'package', t, b, m.id::text);
      user_id := m.client_id; title := t; body := b; route := '/packages';
      RETURN NEXT;
    END LOOP;
  END IF;

  -- Days 2 to 7: this month not paid yet, once per month.
  IF extract(day FROM today) BETWEEN 2 AND 7 THEN
    FOR m IN SELECT pm.id, pm.client_id, p.name, p.price, pr.full_name
               FROM package_members pm
               JOIN monthly_packages p ON p.id = pm.package_id
               JOIN profiles pr ON pr.id = pm.provider_id
              WHERE pm.status = 'active' AND pm.joined_at < date_trunc('month', now()) LOOP
      r := public._period_now(m.id);
      CONTINUE WHEN r.id IS NULL OR r.status <> 'unpaid' OR r.reminded_at IS NOT NULL;
      UPDATE package_periods SET reminded_at = now() WHERE id = r.id;
      t := 'Pay for ' || m.name || ' this month';
      b := 'Send ' || split_part(coalesce(m.full_name, 'your pro'), ' ', 1) || ' $' || trim_scale(r.amount)
           || ' and tap "I''ve paid" to unlock this month''s visits.';
      INSERT INTO notifications (user_id, type, title, body, reference_id) VALUES (m.client_id, 'package', t, b, m.id::text);
      user_id := m.client_id; title := t; body := b; route := '/packages';
      RETURN NEXT;
    END LOOP;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public.package_reminders() FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.package_reminders() TO service_role;
