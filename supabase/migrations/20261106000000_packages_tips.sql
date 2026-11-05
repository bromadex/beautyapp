-- Phase 6: monthly packages (paid to the pro directly, no BeauTap fee),
-- a Tips & trends feed (admins and verified pros), and public numbers for
-- the marketing page.

-- =====================================================================
-- Monthly packages
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.monthly_packages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 60),
  description text CHECK (description IS NULL OR length(description) <= 300),
  price numeric(10,2) NOT NULL CHECK (price > 0 AND price <= 2000),
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS monthly_packages_provider ON public.monthly_packages(provider_id);

CREATE TABLE IF NOT EXISTS public.monthly_package_items (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES public.monthly_packages(id) ON DELETE CASCADE,
  service_id uuid NOT NULL REFERENCES services(id) ON DELETE CASCADE,
  tier_id uuid REFERENCES service_tiers(id) ON DELETE SET NULL,
  quantity smallint NOT NULL DEFAULT 1 CHECK (quantity BETWEEN 1 AND 31),
  UNIQUE (package_id, service_id)
);

CREATE TABLE IF NOT EXISTS public.package_members (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  package_id uuid NOT NULL REFERENCES public.monthly_packages(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'cancelled')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  cancelled_at timestamptz
);
CREATE UNIQUE INDEX IF NOT EXISTS package_members_one_active
  ON public.package_members(package_id, client_id) WHERE status = 'active';

-- One row per member per month: unpaid -> claimed ("I've sent it") -> paid.
CREATE TABLE IF NOT EXISTS public.package_periods (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  member_id uuid NOT NULL REFERENCES public.package_members(id) ON DELETE CASCADE,
  month date NOT NULL,
  amount numeric(10,2) NOT NULL,
  status text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'claimed', 'paid')),
  method text,
  claimed_at timestamptz,
  paid_at timestamptz,
  UNIQUE (member_id, month)
);

-- A booking made as one of a package's visits.
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS package_period_id uuid REFERENCES public.package_periods(id) ON DELETE SET NULL;

ALTER TABLE public.monthly_packages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.monthly_package_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_members ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.package_periods ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS mp_read ON public.monthly_packages;
CREATE POLICY mp_read ON public.monthly_packages FOR SELECT
  USING (is_active OR provider_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS mp_write ON public.monthly_packages;
CREATE POLICY mp_write ON public.monthly_packages FOR ALL TO authenticated
  USING (provider_id = auth.uid()) WITH CHECK (provider_id = auth.uid());

DROP POLICY IF EXISTS mpi_read ON public.monthly_package_items;
CREATE POLICY mpi_read ON public.monthly_package_items FOR SELECT USING (
  EXISTS (SELECT 1 FROM monthly_packages p WHERE p.id = package_id
           AND (p.is_active OR p.provider_id = auth.uid() OR public.is_admin())));
DROP POLICY IF EXISTS mpi_write ON public.monthly_package_items;
CREATE POLICY mpi_write ON public.monthly_package_items FOR ALL TO authenticated
  USING (EXISTS (SELECT 1 FROM monthly_packages p WHERE p.id = package_id AND p.provider_id = auth.uid()))
  WITH CHECK (EXISTS (SELECT 1 FROM monthly_packages p WHERE p.id = package_id AND p.provider_id = auth.uid())
              AND EXISTS (SELECT 1 FROM services s WHERE s.id = service_id AND s.provider_id = auth.uid()));

-- Members and payments change only through the functions below.
DROP POLICY IF EXISTS pm_read ON public.package_members;
CREATE POLICY pm_read ON public.package_members FOR SELECT TO authenticated
  USING (client_id = auth.uid() OR provider_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS pp_read ON public.package_periods;
CREATE POLICY pp_read ON public.package_periods FOR SELECT TO authenticated
  USING (EXISTS (SELECT 1 FROM package_members m WHERE m.id = member_id
                  AND (m.client_id = auth.uid() OR m.provider_id = auth.uid() OR public.is_admin())));
REVOKE INSERT, UPDATE, DELETE ON public.package_members, public.package_periods FROM anon, authenticated;

-- First day of this month in Harare.
CREATE OR REPLACE FUNCTION public._this_month() RETURNS date
LANGUAGE sql STABLE AS $$ SELECT date_trunc('month', now() AT TIME ZONE 'Africa/Harare')::date $$;

-- This month's row for a member, created when first needed.
CREATE OR REPLACE FUNCTION public._period_now(p_member uuid) RETURNS package_periods
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m package_members; r package_periods;
BEGIN
  SELECT * INTO m FROM package_members WHERE id = p_member;
  IF NOT FOUND OR m.status <> 'active' THEN RETURN NULL; END IF;
  INSERT INTO package_periods (member_id, month, amount)
  SELECT m.id, public._this_month(), p.price FROM monthly_packages p WHERE p.id = m.package_id
  ON CONFLICT (member_id, month) DO NOTHING;
  SELECT * INTO r FROM package_periods WHERE member_id = m.id AND month = public._this_month();
  RETURN r;
END $$;
REVOKE ALL ON FUNCTION public._period_now(uuid) FROM public, anon, authenticated;

CREATE OR REPLACE FUNCTION public.join_package(p_package uuid) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE p monthly_packages; mid uuid;
BEGIN
  IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Please sign in'; END IF;
  SELECT * INTO p FROM monthly_packages WHERE id = p_package AND is_active;
  IF NOT FOUND THEN RAISE EXCEPTION 'This package is no longer available'; END IF;
  IF p.provider_id = auth.uid() THEN RAISE EXCEPTION 'You can''t join your own package'; END IF;
  SELECT id INTO mid FROM package_members WHERE package_id = p.id AND client_id = auth.uid() AND status = 'active';
  IF mid IS NULL THEN
    INSERT INTO package_members (package_id, provider_id, client_id) VALUES (p.id, p.provider_id, auth.uid())
    RETURNING id INTO mid;
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p.provider_id, 'package', 'New package member',
            coalesce((SELECT full_name FROM profiles WHERE id = auth.uid()), 'A client')
            || ' joined ' || p.name || '. They''ll send you ' || '$' || p.price || ' for this month.', mid::text);
  END IF;
  PERFORM public._period_now(mid);
  RETURN mid;
END $$;
GRANT EXECUTE ON FUNCTION public.join_package(uuid) TO authenticated;

-- Client: "I've sent this month's payment".
CREATE OR REPLACE FUNCTION public.claim_package_payment(p_member uuid, p_method text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m package_members; r package_periods;
BEGIN
  SELECT * INTO m FROM package_members WHERE id = p_member AND client_id = auth.uid() AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'Package not found'; END IF;
  r := public._period_now(m.id);
  IF r.status = 'paid' THEN RETURN; END IF;
  UPDATE package_periods SET status = 'claimed', claimed_at = now(),
         method = CASE WHEN p_method IN ('ecocash','innbucks','onemoney','bank','cash') THEN p_method ELSE 'cash' END
   WHERE id = r.id;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (m.provider_id, 'package', 'Package payment to check',
          coalesce((SELECT full_name FROM profiles WHERE id = auth.uid()), 'A client')
          || ' says they sent $' || r.amount || ' for this month. Tap Received once it''s in.', m.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.claim_package_payment(uuid, text) TO authenticated;

-- Pro: "Received" (also for cash handed over without a claim).
CREATE OR REPLACE FUNCTION public.confirm_package_payment(p_member uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m package_members; r package_periods;
BEGIN
  SELECT * INTO m FROM package_members WHERE id = p_member AND provider_id = auth.uid() AND status = 'active';
  IF NOT FOUND THEN RAISE EXCEPTION 'Member not found'; END IF;
  r := public._period_now(m.id);
  UPDATE package_periods SET status = 'paid', paid_at = now(), method = coalesce(method, 'cash') WHERE id = r.id;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (m.client_id, 'package', 'Package payment received',
          'Your visits for this month are unlocked. Book them any time.', m.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.confirm_package_payment(uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_package(p_member uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m package_members;
BEGIN
  SELECT * INTO m FROM package_members WHERE id = p_member AND status = 'active'
     AND (client_id = auth.uid() OR provider_id = auth.uid());
  IF NOT FOUND THEN RAISE EXCEPTION 'Package not found'; END IF;
  UPDATE package_members SET status = 'cancelled', cancelled_at = now() WHERE id = m.id;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN auth.uid() = m.client_id THEN m.provider_id ELSE m.client_id END, 'package', 'Package cancelled',
          'A monthly package was cancelled. Visits already paid for this month can still be booked.', m.id::text);
END $$;
GRANT EXECUTE ON FUNCTION public.cancel_package(uuid) TO authenticated;

-- Visits left this month, per service, for a member.
CREATE OR REPLACE FUNCTION public.package_visits_left(p_member uuid)
RETURNS TABLE (service_id uuid, tier_id uuid, included int, used int)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT i.service_id, i.tier_id, i.quantity::int,
         (SELECT count(*)::int FROM bookings b
           JOIN package_periods pr ON pr.id = b.package_period_id
          WHERE pr.member_id = m.id AND pr.month = public._this_month()
            AND b.service_id = i.service_id AND b.status IN ('pending', 'confirmed', 'completed'))
    FROM package_members m
    JOIN monthly_package_items i ON i.package_id = m.package_id
   WHERE m.id = p_member AND (m.client_id = auth.uid() OR m.provider_id = auth.uid() OR public.is_admin());
$$;
GRANT EXECUTE ON FUNCTION public.package_visits_left(uuid) TO authenticated;

-- Everything the client's "My packages" page needs (creates this month's row).
CREATE OR REPLACE FUNCTION public.my_packages() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m record;res jsonb := '[]'::jsonb; r package_periods;
BEGIN
  FOR m IN SELECT pm.*, p.name, p.price, p.description, pr.full_name AS pro_name, pr.avatar_url AS pro_avatar
             FROM package_members pm
             JOIN monthly_packages p ON p.id = pm.package_id
             JOIN profiles pr ON pr.id = pm.provider_id
            WHERE pm.client_id = auth.uid()
              AND (pm.status = 'active' OR pm.cancelled_at > now() - interval '31 days')
            ORDER BY pm.joined_at DESC LOOP
    IF m.status = 'active' THEN r := public._period_now(m.id);
    ELSE SELECT * INTO r FROM package_periods WHERE member_id = m.id AND month = public._this_month();
    END IF;
    res := res || jsonb_build_object(
      'member_id', m.id, 'package_id', m.package_id, 'provider_id', m.provider_id, 'status', m.status,
      'name', m.name, 'price', m.price, 'description', m.description,
      'pro_name', m.pro_name, 'pro_avatar', m.pro_avatar,
      'month', r.month, 'period_id', r.id, 'pay_status', coalesce(r.status, 'unpaid'),
      'items', coalesce((SELECT jsonb_agg(jsonb_build_object(
                  'service_id', v.service_id, 'tier_id', v.tier_id, 'included', v.included, 'used', v.used,
                  'service_name', s.service_name, 'tier_name', t.name))
                FROM public.package_visits_left(m.id) v
                JOIN services s ON s.id = v.service_id
                LEFT JOIN service_tiers t ON t.id = v.tier_id), '[]'::jsonb));
  END LOOP;
  RETURN res;
END $$;
GRANT EXECUTE ON FUNCTION public.my_packages() TO authenticated;

-- The pro's members for one package, with this month's payment.
CREATE OR REPLACE FUNCTION public.package_members_for(p_package uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m record;res jsonb := '[]'::jsonb; r package_periods;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM monthly_packages WHERE id = p_package AND provider_id = auth.uid()) THEN
    RAISE EXCEPTION 'Package not found';
  END IF;
  FOR m IN SELECT pm.*, pr.full_name, pr.avatar_url, pr.phone
             FROM package_members pm JOIN profiles pr ON pr.id = pm.client_id
            WHERE pm.package_id = p_package AND pm.status = 'active' ORDER BY pm.joined_at LOOP
    r := public._period_now(m.id);
    res := res || jsonb_build_object(
      'member_id', m.id, 'client_id', m.client_id, 'name', m.full_name, 'avatar_url', m.avatar_url,
      'phone', m.phone, 'pay_status', r.status, 'method', r.method, 'claimed_at', r.claimed_at,
      'amount', r.amount,
      'last_paid', (SELECT max(month) FROM package_periods WHERE member_id = m.id AND status = 'paid'),
      'included', (SELECT coalesce(sum(v.included), 0) FROM public.package_visits_left(m.id) v),
      'used', (SELECT coalesce(sum(v.used), 0) FROM public.package_visits_left(m.id) v));
  END LOOP;
  RETURN res;
END $$;
GRANT EXECUTE ON FUNCTION public.package_members_for(uuid) TO authenticated;

-- Package visits on bookings: $0 to pay, only while this month is paid and
-- there are visits left for that service. Named "zzz" to run after the
-- other booking triggers, which work out the price and deposit.

CREATE OR REPLACE FUNCTION public.bookings_package_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r package_periods; m package_members; inc int; used int;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    NEW.package_period_id := OLD.package_period_id;
  END IF;
  IF NEW.package_period_id IS NULL THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    SELECT * INTO r FROM package_periods WHERE id = NEW.package_period_id;
    SELECT * INTO m FROM package_members WHERE id = r.member_id;
    IF m.id IS NULL OR m.client_id IS DISTINCT FROM NEW.client_id OR m.provider_id <> NEW.provider_id THEN
      RAISE EXCEPTION 'This package isn''t yours';
    END IF;
    IF r.status <> 'paid' OR r.month <> public._this_month() THEN
      RAISE EXCEPTION 'This month''s package payment hasn''t been confirmed yet';
    END IF;
    SELECT quantity INTO inc FROM monthly_package_items i
     WHERE i.package_id = m.package_id AND i.service_id = NEW.service_id;
    IF inc IS NULL THEN RAISE EXCEPTION 'This service isn''t in your package'; END IF;
    SELECT count(*) INTO used FROM bookings b
     WHERE b.package_period_id = r.id AND b.service_id = NEW.service_id
       AND b.status IN ('pending', 'confirmed', 'completed');
    IF used >= inc THEN RAISE EXCEPTION 'You''ve used all of this month''s visits for this service'; END IF;
  END IF;
  -- Covered by the package. Extras and travel are paid on the day.
  NEW.total_price := coalesce(NEW.addons_total, 0) + coalesce(NEW.travel_fee, 0);
  NEW.deposit_amount := 0;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bookings_zzz_package ON bookings;
CREATE TRIGGER trg_bookings_zzz_package BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_package_guard();

-- =====================================================================
-- Tips & trends
-- =====================================================================

CREATE TABLE IF NOT EXISTS public.tips (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  author_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  title text NOT NULL CHECK (length(trim(title)) BETWEEN 5 AND 90),
  body text NOT NULL CHECK (length(trim(body)) BETWEEN 40 AND 6000),
  category text NOT NULL DEFAULT 'How-to'
    CHECK (category IN ('Aftercare', 'Trending', 'How-to', 'Hair care', 'Skin', 'Nails', 'Barbering')),
  cover_url text CHECK (cover_url IS NULL OR length(cover_url) <= 500),
  service_id uuid REFERENCES services(id) ON DELETE SET NULL,
  by_beautap boolean NOT NULL DEFAULT false,
  is_hidden boolean NOT NULL DEFAULT false,
  hidden_reason text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS tips_recent ON public.tips(created_at DESC) WHERE NOT is_hidden;

ALTER TABLE public.tips ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tips_read ON public.tips;
CREATE POLICY tips_read ON public.tips FOR SELECT
  USING (NOT is_hidden OR author_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS tips_insert ON public.tips;
CREATE POLICY tips_insert ON public.tips FOR INSERT TO authenticated WITH CHECK (
  author_id = auth.uid()
  AND (public.is_admin() OR EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND is_verified)));
DROP POLICY IF EXISTS tips_update ON public.tips;
CREATE POLICY tips_update ON public.tips FOR UPDATE TO authenticated
  USING (author_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS tips_delete ON public.tips;
CREATE POLICY tips_delete ON public.tips FOR DELETE TO authenticated
  USING (author_id = auth.uid() OR public.is_admin());

-- Only admins hide or unhide, or post as BeauTap. A linked service must be
-- the author's own.
CREATE OR REPLACE FUNCTION public.tips_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN
    IF TG_OP = 'INSERT' THEN
      NEW.is_hidden := false; NEW.hidden_reason := NULL; NEW.by_beautap := false;
    ELSE
      NEW.is_hidden := OLD.is_hidden; NEW.hidden_reason := OLD.hidden_reason; NEW.by_beautap := OLD.by_beautap;
      NEW.author_id := OLD.author_id;
    END IF;
  END IF;
  IF NEW.service_id IS NOT NULL AND NOT EXISTS
     (SELECT 1 FROM services WHERE id = NEW.service_id AND provider_id = NEW.author_id) THEN
    NEW.service_id := NULL;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_tips_guard ON public.tips;
CREATE TRIGGER trg_tips_guard BEFORE INSERT OR UPDATE ON public.tips
  FOR EACH ROW EXECUTE FUNCTION public.tips_guard();

-- Tell the author when an admin hides their tip.
CREATE OR REPLACE FUNCTION public.tips_hidden_notice() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.is_hidden AND NOT OLD.is_hidden AND NEW.author_id <> coalesce(auth.uid(), '00000000-0000-0000-0000-000000000000') THEN
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (NEW.author_id, 'tip', 'Your tip was hidden',
            '"' || NEW.title || '" is no longer shown. Reason: ' || coalesce(NEW.hidden_reason, 'it broke the tips rules') || '.',
            NEW.id::text);
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_tips_hidden_notice ON public.tips;
CREATE TRIGGER trg_tips_hidden_notice AFTER UPDATE ON public.tips
  FOR EACH ROW EXECUTE FUNCTION public.tips_hidden_notice();

GRANT SELECT ON public.tips TO anon;

-- =====================================================================
-- Marketing page numbers (real, rounded down so they don't jump around)
-- =====================================================================
CREATE OR REPLACE FUNCTION public.public_stats() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'pros', (SELECT count(*) FROM provider_profiles pp
              WHERE NOT coalesce(pp.is_hidden, false) AND public.provider_has_location(pp.provider_id)),
    'rating', (SELECT round(avg(rating)::numeric, 1) FROM reviews),
    'reviews', (SELECT count(*) FROM reviews),
    'cities', (SELECT coalesce(jsonb_agg(DISTINCT c.name), '[]'::jsonb)
                 FROM provider_profiles pp JOIN cities c ON c.id = pp.city_id
                WHERE NOT coalesce(pp.is_hidden, false) AND public.provider_has_location(pp.provider_id)));
$$;
GRANT EXECUTE ON FUNCTION public.public_stats() TO anon, authenticated;
