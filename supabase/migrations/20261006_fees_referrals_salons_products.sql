-- BeauTap's own fees (plans, featured, salon plan, product packs), a manual
-- EcoCash backup for them, pro referrals, salons and product ads.

-- =====================================================================
-- 1. Fees: one place that prices and applies everything BeauTap charges
-- =====================================================================
CREATE TABLE IF NOT EXISTS app_settings (
  key text PRIMARY KEY,
  value text,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS app_settings_read ON app_settings;
CREATE POLICY app_settings_read ON app_settings FOR SELECT
  USING (key IN ('beautap_ecocash_number', 'beautap_ecocash_name') OR public.is_admin());
DROP POLICY IF EXISTS app_settings_admin ON app_settings;
CREATE POLICY app_settings_admin ON app_settings FOR ALL
  USING (public.is_admin()) WITH CHECK (public.is_admin());

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_purpose_check;
ALTER TABLE payments ADD CONSTRAINT payments_purpose_check
  CHECK (purpose IN ('booking', 'activation', 'subscription', 'deposit', 'featured', 'product_pack'));

CREATE OR REPLACE FUNCTION public._fee_price(p_purpose text, p_plan text) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_purpose = 'subscription' AND p_plan = 'activation' THEN 3
    WHEN p_purpose = 'subscription' AND p_plan = 'monthly' THEN 5
    WHEN p_purpose = 'subscription' AND p_plan = 'salon' THEN 15
    WHEN p_purpose = 'featured' THEN 3
    WHEN p_purpose = 'product_pack' THEN 5
  END::numeric;
$$;

-- Extends (or starts) a pro's plan by some months.
CREATE OR REPLACE FUNCTION public._extend_plan(p_user uuid, p_months int, p_plan text, p_amount numeric, p_ref text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s subscriptions; base date;
BEGIN
  SELECT * INTO s FROM subscriptions WHERE provider_id = p_user;
  base := CASE WHEN s.status = 'active' AND s.end_date >= current_date THEN s.end_date ELSE current_date END;
  IF FOUND THEN
    UPDATE subscriptions
       SET start_date = CASE WHEN s.status = 'active' AND s.end_date >= current_date THEN s.start_date ELSE current_date END,
           end_date = (base + make_interval(months => p_months))::date,
           status = 'active',
           plan = coalesce(p_plan, s.plan, 'monthly'),
           amount_paid = coalesce(p_amount, s.amount_paid),
           payment_ref = coalesce(p_ref, s.payment_ref),
           updated_at = now()
     WHERE provider_id = p_user;
  ELSE
    INSERT INTO subscriptions (provider_id, start_date, end_date, status, plan, amount_paid, payment_ref)
    VALUES (p_user, current_date, (current_date + make_interval(months => p_months))::date, 'active',
            coalesce(p_plan, 'monthly'), coalesce(p_amount, 0), p_ref);
  END IF;
  UPDATE provider_profiles SET is_hidden = false WHERE provider_id = p_user;
END $$;

-- Applies a paid fee. Paynow calls it after its own payments row is paid
-- (p_record = false); manual EcoCash approvals record the payment here.
CREATE OR REPLACE FUNCTION public._apply_fee(
  p_user uuid, p_purpose text, p_plan text, p_amount numeric, p_ref text, p_record boolean DEFAULT false)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE until timestamptz;
BEGIN
  IF p_record THEN
    INSERT INTO payments (client_id, provider_id, amount, method, status, transaction_ref, paid_at,
                          gateway, purpose, meta)
    VALUES (p_user, p_user, p_amount, 'mobile_money', 'paid', p_ref, now(), 'manual', p_purpose,
            jsonb_build_object('plan', p_plan));
  END IF;

  IF p_purpose = 'subscription' THEN
    PERFORM public._extend_plan(p_user, 1, coalesce(p_plan, 'monthly'), p_amount, p_ref);
    PERFORM public._check_referral(p_user);
  ELSIF p_purpose = 'featured' THEN
    SELECT greatest(now(), coalesce(featured_until, now())) + interval '7 days' INTO until
      FROM provider_profiles WHERE provider_id = p_user;
    UPDATE provider_profiles SET featured_until = until WHERE provider_id = p_user;
  ELSIF p_purpose = 'product_pack' THEN
    INSERT INTO product_packs (provider_id, items, expires_at, source, payment_ref)
    VALUES (p_user, 20, now() + interval '30 days', CASE WHEN p_record THEN 'manual' ELSE 'paynow' END, p_ref);
  END IF;
END $$;

-- "I sent EcoCash to BeauTap" claims, checked by an admin.
CREATE TABLE IF NOT EXISTS fee_claims (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  purpose text NOT NULL CHECK (purpose IN ('subscription', 'featured', 'product_pack')),
  plan text,
  amount numeric(10,2) NOT NULL,
  reference text NOT NULL CHECK (length(reference) BETWEEN 4 AND 60),
  status text NOT NULL DEFAULT 'claimed' CHECK (status IN ('claimed', 'approved', 'rejected')),
  note text,
  created_at timestamptz NOT NULL DEFAULT now(),
  decided_at timestamptz,
  decided_by uuid
);
CREATE UNIQUE INDEX IF NOT EXISTS fee_claims_one_open ON fee_claims(user_id, purpose) WHERE status = 'claimed';
CREATE UNIQUE INDEX IF NOT EXISTS fee_claims_ref ON fee_claims(reference) WHERE status <> 'rejected';
ALTER TABLE fee_claims ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS fee_claims_read ON fee_claims;
CREATE POLICY fee_claims_read ON fee_claims FOR SELECT USING (user_id = auth.uid() OR public.is_admin());

CREATE OR REPLACE FUNCTION public.claim_fee_payment(p_purpose text, p_plan text, p_reference text)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); price numeric; ref text; new_id uuid; who text;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Only beauty pros can pay for plans';
  END IF;
  price := public._fee_price(p_purpose, CASE WHEN p_purpose = 'subscription' THEN p_plan END);
  IF price IS NULL THEN RAISE EXCEPTION 'Invalid plan'; END IF;
  IF p_plan = 'salon' AND NOT EXISTS (SELECT 1 FROM salons WHERE owner_id = uid) THEN
    RAISE EXCEPTION 'Create your salon first';
  END IF;
  IF p_purpose = 'subscription' AND p_plan <> 'salon' AND EXISTS (
       SELECT 1 FROM subscriptions WHERE provider_id = uid AND plan = 'salon'
          AND status = 'active' AND end_date >= current_date) THEN
    RAISE EXCEPTION 'Your salon plan already covers you. Add another salon month instead.';
  END IF;
  ref := upper(regexp_replace(coalesce(p_reference, ''), '\s', '', 'g'));
  IF length(ref) < 4 THEN RAISE EXCEPTION 'Enter the transaction ID from your EcoCash SMS'; END IF;
  IF EXISTS (SELECT 1 FROM fee_claims WHERE reference = ref AND status <> 'rejected') THEN
    RAISE EXCEPTION 'This transaction ID was already used';
  END IF;
  IF EXISTS (SELECT 1 FROM fee_claims WHERE user_id = uid AND purpose = p_purpose AND status = 'claimed') THEN
    RAISE EXCEPTION 'We are still checking your last payment';
  END IF;

  INSERT INTO fee_claims (user_id, purpose, plan, amount, reference)
  VALUES (uid, p_purpose, CASE WHEN p_purpose = 'subscription' THEN p_plan END, price, ref)
  RETURNING id INTO new_id;

  SELECT coalesce(nullif(trim(full_name), ''), 'A pro') INTO who FROM profiles WHERE id = uid;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  SELECT a.user_id, 'fee_claim', 'EcoCash payment to check',
         who || ' sent $' || trim(to_char(price, 'FM999990.00')) || ' (ref ' || ref || ').', new_id::text
    FROM admins a;
  RETURN new_id;
END $$;

CREATE OR REPLACE FUNCTION public.review_fee_claim(p_claim uuid, p_approve boolean, p_note text DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c fee_claims; what text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Not allowed'; END IF;
  SELECT * INTO c FROM fee_claims WHERE id = p_claim FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Claim not found'; END IF;
  IF c.status <> 'claimed' THEN RAISE EXCEPTION 'Already answered'; END IF;

  UPDATE fee_claims SET status = CASE WHEN p_approve THEN 'approved' ELSE 'rejected' END,
         note = nullif(trim(p_note), ''), decided_at = now(), decided_by = auth.uid()
   WHERE id = c.id;

  what := CASE c.purpose WHEN 'featured' THEN 'featured week'
                         WHEN 'product_pack' THEN 'product pack'
                         ELSE CASE c.plan WHEN 'salon' THEN 'salon plan' ELSE 'Pro plan' END END;
  IF p_approve THEN
    PERFORM public._apply_fee(c.user_id, c.purpose, c.plan, c.amount, c.reference, true);
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (c.user_id, 'fee_update', 'Payment received', 'Thanks! Your ' || what || ' is now active.', c.id::text);
  ELSE
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (c.user_id, 'fee_update', 'Payment not found',
            'We couldn''t find your $' || trim(to_char(c.amount, 'FM999990.00')) || ' EcoCash payment (ref '
            || c.reference || ').' || coalesce(' ' || nullif(trim(p_note), ''), '') || ' Please check and try again.',
            c.id::text);
  END IF;
END $$;

-- =====================================================================
-- 2. Referrals (pros only)
-- =====================================================================
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS referral_code text;
CREATE UNIQUE INDEX IF NOT EXISTS provider_referral_code ON provider_profiles(referral_code);

CREATE TABLE IF NOT EXISTS referral_rewards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  months int NOT NULL,
  year int NOT NULL,
  granted_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS referrals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  referrer_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  referred_id uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  qualified_at timestamptz,
  reward_id uuid REFERENCES referral_rewards(id) ON DELETE SET NULL,
  CHECK (referrer_id <> referred_id)
);
CREATE INDEX IF NOT EXISTS referrals_referrer ON referrals(referrer_id);
ALTER TABLE referrals ENABLE ROW LEVEL SECURITY;
ALTER TABLE referral_rewards ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS referrals_read ON referrals;
CREATE POLICY referrals_read ON referrals FOR SELECT
  USING (auth.uid() IN (referrer_id, referred_id) OR public.is_admin());
DROP POLICY IF EXISTS referral_rewards_read ON referral_rewards;
CREATE POLICY referral_rewards_read ON referral_rewards FOR SELECT
  USING (auth.uid() = referrer_id OR public.is_admin());

-- Plan payments a pro has made to BeauTap (Paynow or manual EcoCash).
CREATE OR REPLACE FUNCTION public._plan_payments(p_user uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM payments
   WHERE client_id = p_user AND purpose = 'subscription' AND status = 'paid';
$$;

CREATE OR REPLACE FUNCTION public._grant_referral_rewards(p_referrer uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE yr int := extract(year FROM now() AT TIME ZONE 'Africa/Harare')::int; used int; pair uuid[]; rid uuid;
BEGIN
  LOOP
    SELECT coalesce(sum(months), 0) INTO used FROM referral_rewards WHERE referrer_id = p_referrer AND year = yr;
    EXIT WHEN used + 2 > 6;
    SELECT array_agg(id) INTO pair FROM (
      SELECT id FROM referrals
       WHERE referrer_id = p_referrer AND qualified_at IS NOT NULL AND reward_id IS NULL
       ORDER BY qualified_at LIMIT 2) x;
    EXIT WHEN coalesce(array_length(pair, 1), 0) < 2;

    INSERT INTO referral_rewards (referrer_id, months, year) VALUES (p_referrer, 2, yr) RETURNING id INTO rid;
    UPDATE referrals SET reward_id = rid WHERE id = ANY (pair);
    PERFORM public._extend_plan(p_referrer, 2, NULL, NULL, 'referral');
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p_referrer, 'referral', 'You earned 2 free Pro months',
            'Two pros you invited are verified and paying. Your Pro plan was extended by 2 months.', rid::text);
  END LOOP;
END $$;

-- Call whenever a pro pays for a plan or gets ID-verified.
CREATE OR REPLACE FUNCTION public._check_referral(p_user uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r referrals; who text;
BEGIN
  UPDATE referrals SET qualified_at = now()
   WHERE referred_id = p_user AND qualified_at IS NULL
     AND coalesce((SELECT is_verified FROM profiles WHERE id = p_user), false)
     AND public._plan_payments(p_user) >= 2
  RETURNING * INTO r;
  IF r.id IS NOT NULL THEN
    SELECT coalesce(nullif(trim(full_name), ''), 'A pro you invited') INTO who FROM profiles WHERE id = p_user;
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (r.referrer_id, 'referral', 'Referral counted',
            who || ' is verified and has paid twice. Every 2 of these gives you 2 free Pro months.', r.id::text);
    PERFORM public._grant_referral_rewards(r.referrer_id);
  END IF;
  -- Rewards held back by the yearly cap are paid once a new year starts.
  PERFORM public._grant_referral_rewards(p_user);
END $$;

CREATE OR REPLACE FUNCTION public.profiles_verified_referral() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  PERFORM public._check_referral(NEW.id);
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_profiles_verified_referral ON profiles;
CREATE TRIGGER trg_profiles_verified_referral AFTER UPDATE OF is_verified ON profiles
  FOR EACH ROW WHEN (NEW.is_verified AND NOT coalesce(OLD.is_verified, false))
  EXECUTE FUNCTION public.profiles_verified_referral();

CREATE OR REPLACE FUNCTION public.my_referrals() RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); paid int; code text; yr int := extract(year FROM now() AT TIME ZONE 'Africa/Harare')::int;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Referrals are for beauty pros';
  END IF;
  paid := public._plan_payments(uid);
  SELECT referral_code INTO code FROM provider_profiles WHERE provider_id = uid;
  IF paid >= 2 AND code IS NULL AND EXISTS (SELECT 1 FROM provider_profiles WHERE provider_id = uid) THEN
    LOOP
      code := upper(substr(translate(encode(extensions.gen_random_bytes(6), 'base64'), '+/=0O1Il', ''), 1, 6));
      EXIT WHEN length(code) = 6 AND NOT EXISTS (SELECT 1 FROM provider_profiles WHERE referral_code = code);
    END LOOP;
    UPDATE provider_profiles SET referral_code = code WHERE provider_id = uid;
  END IF;

  RETURN jsonb_build_object(
    'payments', paid,
    'eligible', paid >= 2,
    'code', CASE WHEN paid >= 2 THEN code END,
    'months_this_year', (SELECT coalesce(sum(months), 0) FROM referral_rewards WHERE referrer_id = uid AND year = yr),
    'months_cap', 6,
    'invited_by', (SELECT p.full_name FROM referrals r JOIN profiles p ON p.id = r.referrer_id WHERE r.referred_id = uid),
    'can_enter_code', NOT EXISTS (SELECT 1 FROM referrals WHERE referred_id = uid)
                      AND paid = 0
                      AND (SELECT created_at FROM profiles WHERE id = uid) > now() - interval '30 days',
    'referrals', coalesce((
      SELECT jsonb_agg(jsonb_build_object(
               'name', coalesce(nullif(trim(p.full_name), ''), 'New pro'),
               'verified', coalesce(p.is_verified, false),
               'payments', least(public._plan_payments(r.referred_id), 2),
               'qualified', r.qualified_at IS NOT NULL,
               'rewarded', r.reward_id IS NOT NULL,
               'joined', r.created_at) ORDER BY r.created_at DESC)
        FROM referrals r JOIN profiles p ON p.id = r.referred_id
       WHERE r.referrer_id = uid), '[]'::jsonb)
  );
END $$;

CREATE OR REPLACE FUNCTION public.use_referral_code(p_code text) RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); ref uuid; who text; refname text;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Referral codes are for beauty pros';
  END IF;
  IF EXISTS (SELECT 1 FROM referrals WHERE referred_id = uid) THEN
    RAISE EXCEPTION 'You already used a referral code';
  END IF;
  IF (SELECT created_at FROM profiles WHERE id = uid) < now() - interval '30 days' THEN
    RAISE EXCEPTION 'Referral codes can only be added in your first 30 days';
  END IF;
  IF public._plan_payments(uid) > 0 THEN
    RAISE EXCEPTION 'Referral codes must be added before your first plan payment';
  END IF;
  SELECT provider_id INTO ref FROM provider_profiles WHERE referral_code = upper(trim(p_code));
  IF ref IS NULL THEN RAISE EXCEPTION 'That code doesn''t exist'; END IF;
  IF ref = uid THEN RAISE EXCEPTION 'You can''t use your own code'; END IF;
  IF public._plan_payments(ref) < 2 THEN RAISE EXCEPTION 'That code isn''t active'; END IF;

  INSERT INTO referrals (referrer_id, referred_id) VALUES (ref, uid);
  SELECT coalesce(nullif(trim(full_name), ''), 'A new pro') INTO who FROM profiles WHERE id = uid;
  SELECT full_name INTO refname FROM profiles WHERE id = ref;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (ref, 'referral', 'Someone used your code',
          who || ' joined with your code. It counts once they''re ID-verified and have paid for 2 months.', uid::text);
  RETURN refname;
END $$;

-- =====================================================================
-- 3. Salons: one $15 plan covers the owner and up to 7 staff
-- =====================================================================
CREATE TABLE IF NOT EXISTS salons (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 60),
  address text CHECK (address IS NULL OR length(address) <= 120),
  invite_code text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE TABLE IF NOT EXISTS salon_members (
  salon_id uuid NOT NULL REFERENCES salons(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL UNIQUE REFERENCES profiles(id) ON DELETE CASCADE,
  role text NOT NULL DEFAULT 'staff' CHECK (role IN ('owner', 'staff')),
  joined_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (salon_id, provider_id)
);
ALTER TABLE salons ENABLE ROW LEVEL SECURITY;
ALTER TABLE salon_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS salons_read ON salons;
CREATE POLICY salons_read ON salons FOR SELECT USING (true);
DROP POLICY IF EXISTS salon_members_read ON salon_members;
CREATE POLICY salon_members_read ON salon_members FOR SELECT USING (true);
-- The invite code is only for the owner's eyes (see my_salon()).
REVOKE SELECT ON salons FROM anon, authenticated;
GRANT SELECT (id, owner_id, name, address, created_at) ON salons TO anon, authenticated;

-- 1 = owner, then staff in the order they joined.
CREATE OR REPLACE FUNCTION public._salon_seat(p_provider uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT seat FROM (
    SELECT m.provider_id, row_number() OVER (PARTITION BY m.salon_id
             ORDER BY (m.role = 'owner') DESC, m.joined_at, m.provider_id)::int AS seat
      FROM salon_members m
     WHERE m.salon_id = (SELECT salon_id FROM salon_members WHERE provider_id = p_provider)) x
   WHERE provider_id = p_provider;
$$;

CREATE OR REPLACE FUNCTION public.provider_is_active(p_provider uuid) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT EXISTS (
    SELECT 1 FROM public.subscriptions
     WHERE provider_id = p_provider AND status = 'active' AND end_date >= current_date
  ) OR (
    EXISTS (
      SELECT 1 FROM salon_members m
        JOIN salons s ON s.id = m.salon_id
        JOIN subscriptions sub ON sub.provider_id = s.owner_id
       WHERE m.provider_id = p_provider AND sub.plan = 'salon'
         AND sub.status = 'active' AND sub.end_date >= current_date)
    AND public._salon_seat(p_provider) <= 8
  );
$function$;

CREATE OR REPLACE FUNCTION public._new_invite_code() RETURNS text
LANGUAGE plpgsql AS $$
DECLARE c text;
BEGIN
  LOOP
    c := upper(substr(translate(encode(extensions.gen_random_bytes(6), 'base64'), '+/=0O1Il', ''), 1, 6));
    EXIT WHEN length(c) = 6 AND NOT EXISTS (SELECT 1 FROM salons WHERE invite_code = c);
  END LOOP;
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION public.create_salon(p_name text, p_address text DEFAULT NULL) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); sid uuid;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Only beauty pros can create a salon';
  END IF;
  IF EXISTS (SELECT 1 FROM salon_members WHERE provider_id = uid) THEN
    RAISE EXCEPTION 'You are already part of a salon';
  END IF;
  INSERT INTO salons (owner_id, name, address, invite_code)
  VALUES (uid, trim(p_name), nullif(trim(p_address), ''), public._new_invite_code()) RETURNING id INTO sid;
  INSERT INTO salon_members (salon_id, provider_id, role) VALUES (sid, uid, 'owner');
  RETURN sid;
END $$;

CREATE OR REPLACE FUNCTION public.update_salon(p_name text, p_address text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  UPDATE salons SET name = trim(p_name), address = nullif(trim(p_address), '') WHERE owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Only the salon owner can do this'; END IF;
END $$;

CREATE OR REPLACE FUNCTION public.new_salon_invite_code() RETURNS text
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE c text := public._new_invite_code();
BEGIN
  UPDATE salons SET invite_code = c WHERE owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Only the salon owner can do this'; END IF;
  RETURN c;
END $$;

CREATE OR REPLACE FUNCTION public.join_salon(p_code text) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); s salons; seat int; who text;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Only beauty pros can join a salon';
  END IF;
  IF EXISTS (SELECT 1 FROM salon_members WHERE provider_id = uid) THEN
    RAISE EXCEPTION 'You are already part of a salon. Leave it first.';
  END IF;
  SELECT * INTO s FROM salons WHERE invite_code = upper(trim(p_code));
  IF NOT FOUND THEN RAISE EXCEPTION 'That salon code doesn''t exist'; END IF;
  IF (SELECT count(*) FROM salon_members WHERE salon_id = s.id) >= 30 THEN
    RAISE EXCEPTION 'This salon is full';
  END IF;
  INSERT INTO salon_members (salon_id, provider_id, role) VALUES (s.id, uid, 'staff');
  seat := public._salon_seat(uid);
  SELECT coalesce(nullif(trim(full_name), ''), 'A pro') INTO who FROM profiles WHERE id = uid;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (s.owner_id, 'salon', 'New team member',
          who || ' joined ' || s.name || '.' || CASE WHEN seat > 8
            THEN ' Your salon plan covers 8 people, so they need their own Pro plan.' ELSE '' END,
          s.id::text);
  RETURN jsonb_build_object('salon', s.name, 'seat', seat, 'covered', seat <= 8);
END $$;

CREATE OR REPLACE FUNCTION public.leave_salon() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM salons WHERE owner_id = auth.uid()) THEN
    RAISE EXCEPTION 'You own this salon. Close the salon instead.';
  END IF;
  DELETE FROM salon_members WHERE provider_id = auth.uid();
END $$;

CREATE OR REPLACE FUNCTION public.remove_salon_member(p_provider uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s salons;
BEGIN
  SELECT * INTO s FROM salons WHERE owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Only the salon owner can do this'; END IF;
  IF p_provider = auth.uid() THEN RAISE EXCEPTION 'You can''t remove yourself'; END IF;
  DELETE FROM salon_members WHERE salon_id = s.id AND provider_id = p_provider;
  IF FOUND THEN
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p_provider, 'salon', 'Removed from salon', 'You are no longer part of ' || s.name || '.', s.id::text);
  END IF;
END $$;

CREATE OR REPLACE FUNCTION public.close_salon() RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM salons WHERE owner_id = auth.uid();
  IF NOT FOUND THEN RAISE EXCEPTION 'Only the salon owner can do this'; END IF;
END $$;

-- The caller's salon, with each member's seat and whether the plan covers them.
CREATE OR REPLACE FUNCTION public.my_salon() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'id', s.id, 'name', s.name, 'address', s.address,
    'is_owner', s.owner_id = auth.uid(),
    'invite_code', CASE WHEN s.owner_id = auth.uid() THEN s.invite_code END,
    'plan_active', EXISTS (SELECT 1 FROM subscriptions sub WHERE sub.provider_id = s.owner_id
                             AND sub.plan = 'salon' AND sub.status = 'active' AND sub.end_date >= current_date),
    'plan_until', (SELECT end_date FROM subscriptions sub WHERE sub.provider_id = s.owner_id AND sub.plan = 'salon'),
    'members', (SELECT jsonb_agg(jsonb_build_object(
                   'id', p.id, 'name', p.full_name, 'avatar_url', p.avatar_url, 'role', m.role,
                   'seat', public._salon_seat(m.provider_id),
                   'own_plan', EXISTS (SELECT 1 FROM subscriptions x WHERE x.provider_id = m.provider_id
                                         AND x.status = 'active' AND x.end_date >= current_date AND x.plan <> 'salon'))
                   ORDER BY public._salon_seat(m.provider_id))
                  FROM salon_members m JOIN profiles p ON p.id = m.provider_id WHERE m.salon_id = s.id)
  )
  FROM salons s JOIN salon_members me ON me.salon_id = s.id
  WHERE me.provider_id = auth.uid();
$$;

-- =====================================================================
-- 4. Product ads: 3 free listings; $5 adds 20 more for 30 days
-- =====================================================================
CREATE TABLE IF NOT EXISTS product_packs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  items int NOT NULL DEFAULT 20,
  starts_at timestamptz NOT NULL DEFAULT now(),
  expires_at timestamptz NOT NULL,
  source text,
  payment_ref text
);
ALTER TABLE product_packs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS product_packs_read ON product_packs;
CREATE POLICY product_packs_read ON product_packs FOR SELECT USING (provider_id = auth.uid() OR public.is_admin());

CREATE TABLE IF NOT EXISTS products (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  provider_id uuid NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  name text NOT NULL CHECK (length(trim(name)) BETWEEN 2 AND 60),
  price numeric(10,2) CHECK (price IS NULL OR price >= 0),
  description text CHECK (description IS NULL OR length(description) <= 300),
  image_url text,
  is_active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS products_provider ON products(provider_id, created_at);
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS products_read ON products;
CREATE POLICY products_read ON products FOR SELECT
  USING (is_active OR provider_id = auth.uid() OR public.is_admin());
DROP POLICY IF EXISTS products_own ON products;
CREATE POLICY products_own ON products FOR ALL
  USING (provider_id = auth.uid()) WITH CHECK (provider_id = auth.uid());

CREATE OR REPLACE FUNCTION public._product_allowance(p_provider uuid) RETURNS int
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT 3 + coalesce((SELECT sum(items) FROM product_packs
                        WHERE provider_id = p_provider AND expires_at > now()), 0)::int;
$$;

CREATE OR REPLACE FUNCTION public.my_products_plan() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'allowance', public._product_allowance(auth.uid()),
    'active', (SELECT count(*) FROM products WHERE provider_id = auth.uid() AND is_active),
    'packs', coalesce((SELECT jsonb_agg(jsonb_build_object('items', items, 'expires_at', expires_at) ORDER BY expires_at)
                         FROM product_packs WHERE provider_id = auth.uid() AND expires_at > now()), '[]'::jsonb));
$$;

CREATE OR REPLACE FUNCTION public.products_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE bad text; used int; allowed int;
BEGIN
  NEW.updated_at := now();
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.provider_id := OLD.provider_id;
    NEW.created_at := OLD.created_at;
  END IF;
  IF (SELECT user_type FROM profiles WHERE id = NEW.provider_id) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Only beauty pros can list products';
  END IF;
  bad := coalesce(public._blocked_words(NEW.name || ' ' || coalesce(NEW.description, '')),
                  public._medical_words(NEW.name || ' ' || coalesce(NEW.description, '')));
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'This product can''t be advertised on BeauTap (%). Medical and adult products aren''t allowed.', bad;
  END IF;
  IF NEW.is_active AND (TG_OP = 'INSERT' OR NOT OLD.is_active) THEN
    SELECT count(*) INTO used FROM products WHERE provider_id = NEW.provider_id AND is_active AND id <> NEW.id;
    allowed := public._product_allowance(NEW.provider_id);
    IF used >= allowed THEN
      RAISE EXCEPTION 'You''re using all % listings. Hide one, or add 20 more for $5.', allowed;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_products_guard ON products;
CREATE TRIGGER trg_products_guard BEFORE INSERT OR UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION public.products_guard();

-- When packs run out, hide the newest listings over the limit.
CREATE OR REPLACE FUNCTION public.enforce_product_limits() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n int := 0; k int;
BEGIN
  PERFORM public._bypass();
  FOR r IN
    SELECT provider_id, count(*) AS active, public._product_allowance(provider_id) AS allowed
      FROM products WHERE is_active GROUP BY provider_id
    HAVING count(*) > public._product_allowance(provider_id)
  LOOP
    UPDATE products SET is_active = false
     WHERE id IN (SELECT id FROM products WHERE provider_id = r.provider_id AND is_active
                   ORDER BY created_at DESC LIMIT (r.active - r.allowed));
    GET DIAGNOSTICS k = ROW_COUNT;
    n := n + k;
    INSERT INTO notifications (user_id, type, title, body)
    VALUES (r.provider_id, 'products', 'Some products were hidden',
            'Your product pack ended, so ' || k || ' listing' || CASE WHEN k = 1 THEN ' was' ELSE 's were' END
            || ' hidden. Add 20 more for $5 to show them again.');
  END LOOP;
  RETURN n;
END $$;

SELECT cron.unschedule('beautap-product-limits')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beautap-product-limits');
SELECT cron.schedule('beautap-product-limits', '7 * * * *', 'SELECT public.enforce_product_limits()');

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('products', 'products', true, 5242880, ARRAY['image/jpeg', 'image/png', 'image/webp'])
ON CONFLICT (id) DO NOTHING;
DROP POLICY IF EXISTS "products upload own" ON storage.objects;
CREATE POLICY "products upload own" ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (bucket_id = 'products' AND (storage.foldername(name))[1] = auth.uid()::text);
DROP POLICY IF EXISTS "products delete own" ON storage.objects;
CREATE POLICY "products delete own" ON storage.objects FOR DELETE TO authenticated
  USING (bucket_id = 'products' AND (storage.foldername(name))[1] = auth.uid()::text);

-- =====================================================================
-- Plan summary for the app
-- =====================================================================
CREATE OR REPLACE FUNCTION public.my_plan() RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT jsonb_build_object(
    'plan', CASE WHEN public.provider_is_active(auth.uid()) THEN 'pro' ELSE 'free' END,
    'own_plan', (SELECT plan FROM subscriptions WHERE provider_id = auth.uid()
                  AND status = 'active' AND end_date >= current_date),
    'via_salon', NOT EXISTS (SELECT 1 FROM subscriptions WHERE provider_id = auth.uid()
                              AND status = 'active' AND end_date >= current_date)
                 AND public.provider_is_active(auth.uid()),
    'free_used', public.free_bookings_used(auth.uid()),
    'free_limit', 5,
    'pro_until', (SELECT end_date FROM subscriptions WHERE provider_id = auth.uid() AND status = 'active'),
    'featured_until', (SELECT featured_until FROM provider_profiles WHERE provider_id = auth.uid()),
    'fee_claims', coalesce((SELECT jsonb_agg(jsonb_build_object('purpose', purpose, 'plan', plan, 'amount', amount,
                                     'reference', reference, 'created_at', created_at))
                              FROM fee_claims WHERE user_id = auth.uid() AND status = 'claimed'), '[]'::jsonb)
  );
$$;

-- Permissions -----------------------------------------------------------
DO $$
DECLARE f text;
BEGIN
  FOREACH f IN ARRAY ARRAY[
    'public._extend_plan(uuid, integer, text, numeric, text)',
    'public._apply_fee(uuid, text, text, numeric, text, boolean)',
    'public._plan_payments(uuid)',
    'public._grant_referral_rewards(uuid)',
    'public._check_referral(uuid)',
    'public.profiles_verified_referral()',
    'public.enforce_product_limits()',
    'public._new_invite_code()'
  ] LOOP
    EXECUTE 'REVOKE ALL ON FUNCTION ' || f || ' FROM public, anon, authenticated';
  END LOOP;
  FOREACH f IN ARRAY ARRAY[
    'public.claim_fee_payment(text, text, text)',
    'public.review_fee_claim(uuid, boolean, text)',
    'public.my_referrals()',
    'public.use_referral_code(text)',
    'public.create_salon(text, text)',
    'public.update_salon(text, text)',
    'public.new_salon_invite_code()',
    'public.join_salon(text)',
    'public.leave_salon()',
    'public.remove_salon_member(uuid)',
    'public.close_salon()',
    'public.my_salon()',
    'public.my_products_plan()'
  ] LOOP
    EXECUTE 'REVOKE ALL ON FUNCTION ' || f || ' FROM public, anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION ' || f || ' TO authenticated';
  END LOOP;
END $$;
GRANT EXECUTE ON FUNCTION public._apply_fee(uuid, text, text, numeric, text, boolean) TO service_role;
