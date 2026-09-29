-- 1. Referral rewards are Pro months only. Salon owners bank them; they
--    start when the salon plan ends.
-- 2. Pros can say their gender so clients can choose (e.g. for massage).
-- 3. Product ads: 50 listings for $10, and a $1 boost to the top of the
--    Home products section for 7 days.

-- =====================================================================
-- 1. Referral rewards: Pro months, banked while on a salon plan
-- =====================================================================
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS pro_credit_months int NOT NULL DEFAULT 0;

-- Gives Pro months now, or banks them if a salon plan is covering the pro.
-- Returns true when banked.
CREATE OR REPLACE FUNCTION public._give_pro_months(p_user uuid, p_months int) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE s subscriptions;
BEGIN
  SELECT * INTO s FROM subscriptions WHERE provider_id = p_user;
  IF s.plan = 'salon' AND s.status = 'active' AND s.end_date >= current_date THEN
    UPDATE provider_profiles SET pro_credit_months = pro_credit_months + p_months WHERE provider_id = p_user;
    RETURN true;
  END IF;
  -- Never turn a lapsed salon plan back on: the months are plain Pro months.
  PERFORM public._extend_plan(p_user, p_months,
                              CASE WHEN s.plan IS NULL OR s.plan = 'salon' THEN 'monthly' ELSE s.plan END,
                              NULL, 'referral');
  RETURN false;
END $$;

CREATE OR REPLACE FUNCTION public._grant_referral_rewards(p_referrer uuid) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE yr int := extract(year FROM now() AT TIME ZONE 'Africa/Harare')::int; used int; pair uuid[]; rid uuid;
        banked boolean;
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
    banked := public._give_pro_months(p_referrer, 2);
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (p_referrer, 'referral', 'You earned 2 free Pro months',
            CASE WHEN banked
              THEN 'Two pros you invited are verified and paying. Your salon plan covers you now, so the 2 Pro months are saved and start when it ends.'
              ELSE 'Two pros you invited are verified and paying. Your Pro plan was extended by 2 months.' END,
            rid::text);
  END LOOP;
END $$;

-- Daily: once a salon plan has ended, turn saved months into Pro time.
CREATE OR REPLACE FUNCTION public.apply_referral_credits() RETURNS int
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE r record; n int := 0;
BEGIN
  FOR r IN
    SELECT pp.provider_id, pp.pro_credit_months FROM provider_profiles pp
     WHERE pp.pro_credit_months > 0
       AND NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.provider_id = pp.provider_id AND s.plan = 'salon'
                         AND s.status = 'active' AND s.end_date >= current_date)
  LOOP
    UPDATE provider_profiles SET pro_credit_months = 0 WHERE provider_id = r.provider_id;
    PERFORM public._give_pro_months(r.provider_id, r.pro_credit_months);
    INSERT INTO notifications (user_id, type, title, body)
    VALUES (r.provider_id, 'referral', 'Your saved Pro months have started',
            'Your ' || r.pro_credit_months || ' free Pro months from inviting pros are now active.');
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;
REVOKE ALL ON FUNCTION public.apply_referral_credits() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public._give_pro_months(uuid, int) FROM public, anon, authenticated;

SELECT cron.unschedule('beautap-referral-credits')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beautap-referral-credits');
SELECT cron.schedule('beautap-referral-credits', '15 1 * * *', 'SELECT public.apply_referral_credits()');

-- =====================================================================
-- 2. Pro gender (optional, used by the client filter)
-- =====================================================================
ALTER TABLE provider_profiles ADD COLUMN IF NOT EXISTS gender text;
ALTER TABLE provider_profiles DROP CONSTRAINT IF EXISTS provider_gender_chk;
ALTER TABLE provider_profiles ADD CONSTRAINT provider_gender_chk CHECK (gender IS NULL OR gender IN ('woman', 'man'));

-- =====================================================================
-- 3. Product ads: bigger pack and boosts
-- =====================================================================
ALTER TABLE products ADD COLUMN IF NOT EXISTS boosted_until timestamptz;
CREATE INDEX IF NOT EXISTS products_boosted ON products(boosted_until) WHERE boosted_until IS NOT NULL;

ALTER TABLE payments DROP CONSTRAINT IF EXISTS payments_purpose_check;
ALTER TABLE payments ADD CONSTRAINT payments_purpose_check
  CHECK (purpose IN ('booking', 'activation', 'subscription', 'deposit', 'featured', 'product_pack', 'product_boost'));

ALTER TABLE fee_claims ADD COLUMN IF NOT EXISTS product_id uuid REFERENCES products(id) ON DELETE SET NULL;
ALTER TABLE fee_claims DROP CONSTRAINT IF EXISTS fee_claims_purpose_check;
ALTER TABLE fee_claims ADD CONSTRAINT fee_claims_purpose_check
  CHECK (purpose IN ('subscription', 'featured', 'product_pack', 'product_boost'));

CREATE OR REPLACE FUNCTION public._fee_price(p_purpose text, p_plan text) RETURNS numeric
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_purpose = 'subscription' AND p_plan = 'activation' THEN 3
    WHEN p_purpose = 'subscription' AND p_plan = 'monthly' THEN 5
    WHEN p_purpose = 'subscription' AND p_plan = 'salon' THEN 15
    WHEN p_purpose = 'featured' THEN 3
    WHEN p_purpose = 'product_pack' AND p_plan = 'large' THEN 10
    WHEN p_purpose = 'product_pack' THEN 5
    WHEN p_purpose = 'product_boost' THEN 1
  END::numeric;
$$;

DROP FUNCTION IF EXISTS public._apply_fee(uuid, text, text, numeric, text, boolean);
CREATE OR REPLACE FUNCTION public._apply_fee(
  p_user uuid, p_purpose text, p_plan text, p_amount numeric, p_ref text,
  p_record boolean DEFAULT false, p_product uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE until timestamptz;
BEGIN
  IF p_record THEN
    INSERT INTO payments (client_id, provider_id, amount, method, status, transaction_ref, paid_at,
                          gateway, purpose, meta)
    VALUES (p_user, p_user, p_amount, 'mobile_money', 'paid', p_ref, now(), 'manual', p_purpose,
            jsonb_build_object('plan', p_plan, 'product_id', p_product));
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
    VALUES (p_user, CASE WHEN p_plan = 'large' THEN 50 ELSE 20 END, now() + interval '30 days',
            CASE WHEN p_record THEN 'manual' ELSE 'paynow' END, p_ref);
  ELSIF p_purpose = 'product_boost' THEN
    PERFORM public._bypass();
    UPDATE products SET boosted_until = greatest(now(), coalesce(boosted_until, now())) + interval '7 days'
     WHERE id = p_product AND provider_id = p_user;
  END IF;
END $$;
REVOKE ALL ON FUNCTION public._apply_fee(uuid, text, text, numeric, text, boolean, uuid) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public._apply_fee(uuid, text, text, numeric, text, boolean, uuid) TO service_role;

DROP FUNCTION IF EXISTS public.claim_fee_payment(text, text, text);
CREATE OR REPLACE FUNCTION public.claim_fee_payment(
  p_purpose text, p_plan text, p_reference text, p_product uuid DEFAULT NULL)
RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); price numeric; ref text; new_id uuid; who text;
BEGIN
  IF (SELECT user_type FROM profiles WHERE id = uid) IS DISTINCT FROM 'provider' THEN
    RAISE EXCEPTION 'Only beauty pros can pay for plans';
  END IF;
  price := public._fee_price(p_purpose, CASE WHEN p_purpose IN ('subscription', 'product_pack') THEN p_plan END);
  IF price IS NULL THEN RAISE EXCEPTION 'Invalid plan'; END IF;
  IF p_plan = 'salon' AND NOT EXISTS (SELECT 1 FROM salons WHERE owner_id = uid) THEN
    RAISE EXCEPTION 'Create your salon first';
  END IF;
  IF p_purpose = 'subscription' AND p_plan <> 'salon' AND EXISTS (
       SELECT 1 FROM subscriptions WHERE provider_id = uid AND plan = 'salon'
          AND status = 'active' AND end_date >= current_date) THEN
    RAISE EXCEPTION 'Your salon plan already covers you. Add another salon month instead.';
  END IF;
  IF p_purpose = 'product_boost' AND NOT EXISTS (
       SELECT 1 FROM products WHERE id = p_product AND provider_id = uid AND is_active) THEN
    RAISE EXCEPTION 'Choose one of your showing products to boost';
  END IF;
  ref := upper(regexp_replace(coalesce(p_reference, ''), '\s', '', 'g'));
  IF length(ref) < 4 THEN RAISE EXCEPTION 'Enter the transaction ID from your EcoCash SMS'; END IF;
  IF EXISTS (SELECT 1 FROM fee_claims WHERE reference = ref AND status <> 'rejected') THEN
    RAISE EXCEPTION 'This transaction ID was already used';
  END IF;
  IF EXISTS (SELECT 1 FROM fee_claims WHERE user_id = uid AND purpose = p_purpose AND status = 'claimed') THEN
    RAISE EXCEPTION 'We are still checking your last payment';
  END IF;

  INSERT INTO fee_claims (user_id, purpose, plan, amount, reference, product_id)
  VALUES (uid, p_purpose, CASE WHEN p_purpose IN ('subscription', 'product_pack') THEN p_plan END, price, ref,
          CASE WHEN p_purpose = 'product_boost' THEN p_product END)
  RETURNING id INTO new_id;

  SELECT coalesce(nullif(trim(full_name), ''), 'A pro') INTO who FROM profiles WHERE id = uid;
  INSERT INTO notifications (user_id, type, title, body, reference_id)
  SELECT a.user_id, 'fee_claim', 'EcoCash payment to check',
         who || ' sent $' || trim(to_char(price, 'FM999990.00')) || ' (ref ' || ref || ').', new_id::text
    FROM admins a;
  RETURN new_id;
END $$;
REVOKE ALL ON FUNCTION public.claim_fee_payment(text, text, text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.claim_fee_payment(text, text, text, uuid) TO authenticated;

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
                         WHEN 'product_boost' THEN 'product boost'
                         ELSE CASE c.plan WHEN 'salon' THEN 'salon plan' ELSE 'Pro plan' END END;
  IF p_approve THEN
    PERFORM public._apply_fee(c.user_id, c.purpose, c.plan, c.amount, c.reference, true, c.product_id);
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

-- Home "From beauty pros near you": boosted products first, then newest,
-- only from pros who have set where they work.
CREATE OR REPLACE FUNCTION public.products_feed(p_city text DEFAULT NULL, p_limit int DEFAULT 12) RETURNS jsonb
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT coalesce(jsonb_agg(x ORDER BY x.boosted DESC, x.created_at DESC), '[]'::jsonb) FROM (
    SELECT pr.id, pr.name, pr.price, pr.description, pr.image_url, pr.created_at,
           coalesce(pr.boosted_until > now(), false) AS boosted,
           pr.provider_id, p.full_name AS pro_name, p.avatar_url,
           coalesce(nullif(trim(p.whatsapp_number), ''), p.phone) AS contact,
           c.name AS city, pp.area
      FROM products pr
      JOIN provider_profiles pp ON pp.provider_id = pr.provider_id
      JOIN profiles p ON p.id = pr.provider_id
      JOIN cities c ON c.id = pp.city_id
     WHERE pr.is_active AND NOT coalesce(pp.is_hidden, false)
       AND nullif(trim(pp.area), '') IS NOT NULL
       AND (p_city IS NULL OR p_city = 'All Zimbabwe' OR c.name = p_city)
     ORDER BY coalesce(pr.boosted_until > now(), false) DESC, pr.created_at DESC
     LIMIT greatest(1, least(p_limit, 30))
  ) x;
$$;
GRANT EXECUTE ON FUNCTION public.products_feed(text, int) TO anon, authenticated;

-- Boosts can only come from a payment.
CREATE OR REPLACE FUNCTION public.products_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE bad text; used int; allowed int;
BEGIN
  NEW.updated_at := now();
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    NEW.provider_id := OLD.provider_id;
    NEW.created_at := OLD.created_at;
    NEW.boosted_until := OLD.boosted_until;   -- only a paid boost sets this
  ELSE
    NEW.boosted_until := NULL;
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

-- Show saved (banked) months on the Invite pros screen.
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
    'banked_months', (SELECT pro_credit_months FROM provider_profiles WHERE provider_id = uid),
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

