-- Everyone signed in (even guests) could read every profile's phone
-- number, push token and ban details, and the list of admins. Keep those in
-- a private table. Phone numbers are shown only to the person, admins, and
-- people they have a booking or a package with.

CREATE TABLE IF NOT EXISTS public.profile_private (
  user_id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  phone text,
  fcm_token text,
  banned_at timestamptz,
  banned_reason text,
  hidden_before_ban boolean,
  updated_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE public.profile_private ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS profile_private_read ON public.profile_private;
CREATE POLICY profile_private_read ON public.profile_private FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
-- Written only through profiles (trigger below) and the functions here.
REVOKE INSERT, UPDATE, DELETE ON public.profile_private FROM anon, authenticated;
REVOKE ALL ON public.profile_private FROM anon;

-- Move what's there now (rows already moved keep their values).
INSERT INTO public.profile_private (user_id, phone, fcm_token, banned_at, banned_reason, hidden_before_ban)
SELECT p.id, nullif(trim(p.phone), ''), p.fcm_token, p.banned_at, p.banned_reason, p.hidden_before_ban
  FROM profiles p JOIN auth.users u ON u.id = p.id
 WHERE coalesce(nullif(trim(p.phone), ''), p.fcm_token) IS NOT NULL OR p.banned_at IS NOT NULL
ON CONFLICT (user_id) DO UPDATE SET
  phone = coalesce(EXCLUDED.phone, profile_private.phone),
  fcm_token = coalesce(EXCLUDED.fcm_token, profile_private.fcm_token),
  banned_at = coalesce(EXCLUDED.banned_at, profile_private.banned_at),
  banned_reason = coalesce(EXCLUDED.banned_reason, profile_private.banned_reason),
  hidden_before_ban = coalesce(EXCLUDED.hidden_before_ban, profile_private.hidden_before_ban);

-- Writes to these profiles columns (this app, older app versions, sign-up)
-- go to the private table; the public row keeps them empty.
CREATE OR REPLACE FUNCTION public.profiles_private_fields() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  -- Phone deliberately cleared (saved as empty).
  IF TG_OP = 'UPDATE' AND NEW.phone IS NOT NULL AND trim(NEW.phone) = '' THEN
    UPDATE profile_private SET phone = NULL, updated_at = now() WHERE user_id = NEW.id;
  END IF;
  IF nullif(trim(NEW.phone), '') IS NOT NULL OR NEW.fcm_token IS NOT NULL
     OR NEW.banned_at IS NOT NULL OR NEW.banned_reason IS NOT NULL OR NEW.hidden_before_ban IS NOT NULL THEN
    INSERT INTO profile_private AS v (user_id, phone, fcm_token, banned_at, banned_reason, hidden_before_ban)
    VALUES (NEW.id, nullif(trim(NEW.phone), ''), NEW.fcm_token, NEW.banned_at, NEW.banned_reason, NEW.hidden_before_ban)
    ON CONFLICT (user_id) DO UPDATE SET
      phone = coalesce(EXCLUDED.phone, v.phone),
      fcm_token = coalesce(EXCLUDED.fcm_token, v.fcm_token),
      banned_at = coalesce(EXCLUDED.banned_at, v.banned_at),
      banned_reason = coalesce(EXCLUDED.banned_reason, v.banned_reason),
      hidden_before_ban = coalesce(EXCLUDED.hidden_before_ban, v.hidden_before_ban),
      updated_at = now();
  END IF;
  NEW.phone := NULL;
  NEW.fcm_token := NULL;
  NEW.banned_at := NULL;
  NEW.banned_reason := NULL;
  NEW.hidden_before_ban := NULL;
  RETURN NEW;
END $$;
-- "zzz" so it runs after any other profiles triggers.
DROP TRIGGER IF EXISTS trg_profiles_zzz_private ON profiles;
CREATE TRIGGER trg_profiles_zzz_private BEFORE INSERT OR UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION public.profiles_private_fields();

UPDATE profiles SET phone = NULL, fcm_token = NULL, banned_at = NULL, banned_reason = NULL, hidden_before_ban = NULL
 WHERE phone IS NOT NULL OR fcm_token IS NOT NULL OR banned_at IS NOT NULL
    OR banned_reason IS NOT NULL OR hidden_before_ban IS NOT NULL;

-- A phone number, for server code that is already allowed to see it.
CREATE OR REPLACE FUNCTION public._phone(p_user uuid) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT phone FROM profile_private WHERE user_id = p_user;
$$;
REVOKE ALL ON FUNCTION public._phone(uuid) FROM public, anon, authenticated;

-- What the app reads as profiles.contact_phone: the person, admins, and
-- people they have a booking or a package with.
CREATE OR REPLACE FUNCTION public.contact_phone(p profiles) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT v.phone FROM profile_private v
   WHERE v.user_id = p.id
     AND (auth.uid() = p.id OR public.is_admin()
          OR EXISTS (SELECT 1 FROM bookings b
                      WHERE (b.client_id = auth.uid() AND b.provider_id = p.id)
                         OR (b.provider_id = auth.uid() AND b.client_id = p.id))
          OR EXISTS (SELECT 1 FROM package_members m
                      WHERE (m.client_id = auth.uid() AND m.provider_id = p.id)
                         OR (m.provider_id = auth.uid() AND m.client_id = p.id)));
$$;
GRANT EXECUTE ON FUNCTION public.contact_phone(profiles) TO authenticated;

-- Ban details for the admin users screen.
CREATE OR REPLACE FUNCTION public.ban_reason(p profiles) RETURNS text
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT banned_reason FROM profile_private WHERE user_id = p.id AND (public.is_admin() OR auth.uid() = p.id);
$$;
CREATE OR REPLACE FUNCTION public.banned_on(p profiles) RETURNS timestamptz
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT banned_at FROM profile_private WHERE user_id = p.id AND (public.is_admin() OR auth.uid() = p.id);
$$;
GRANT EXECUTE ON FUNCTION public.ban_reason(profiles), public.banned_on(profiles) TO authenticated;

-- Signing out of push on this phone.
CREATE OR REPLACE FUNCTION public.clear_push_token() RETURNS void
LANGUAGE sql SECURITY DEFINER SET search_path = public AS $$
  UPDATE profile_private SET fcm_token = NULL, updated_at = now() WHERE user_id = auth.uid();
$$;
GRANT EXECUTE ON FUNCTION public.clear_push_token() TO authenticated;

-- The admins list: each person can see only whether they are one; admins
-- see all of it.
ALTER TABLE public.admins ENABLE ROW LEVEL SECURITY;
DO $$
DECLARE pol record;
BEGIN
  FOR pol IN SELECT policyname, cmd FROM pg_policies WHERE schemaname = 'public' AND tablename = 'admins' AND cmd IN ('SELECT', 'ALL') LOOP
    EXECUTE format('DROP POLICY %I ON public.admins', pol.policyname);
  END LOOP;
END $$;
CREATE POLICY admins_read ON public.admins FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());
REVOKE ALL ON public.admins FROM anon;

-- Server functions that showed phone numbers now read the private table.
CREATE OR REPLACE FUNCTION public.my_clients()
RETURNS TABLE(client_key text, client_id uuid, name text, phone text, visits bigint, total_spent numeric,
              last_visit timestamptz, next_booking timestamptz, no_shows bigint, tags text[], has_notes boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  WITH b AS (
    SELECT x.*, public._client_key(x) AS k FROM bookings x WHERE x.provider_id = auth.uid()
  ), g AS (
    SELECT k,
           (array_agg(client_id) FILTER (WHERE client_id IS NOT NULL))[1] AS cid,
           (array_agg(walkin_name ORDER BY created_at DESC) FILTER (WHERE walkin_name IS NOT NULL))[1] AS wname,
           (array_agg(walkin_phone ORDER BY created_at DESC) FILTER (WHERE walkin_phone IS NOT NULL))[1] AS wphone,
           count(*) FILTER (WHERE status = 'completed') AS visits,
           coalesce(sum(total_price) FILTER (WHERE status = 'completed'), 0) AS spent,
           max(booking_time) FILTER (WHERE status = 'completed') AS last_visit,
           min(booking_time) FILTER (WHERE status IN ('pending', 'confirmed') AND booking_time > now()) AS next_booking,
           count(*) FILTER (WHERE no_show_by = 'client') AS no_shows
      FROM b GROUP BY k
  )
  SELECT g.k, g.cid, coalesce(p.full_name, g.wname, 'Client'), coalesce(g.wphone, public._phone(g.cid)),
         g.visits, g.spent, g.last_visit, g.next_booking, g.no_shows,
         coalesce(r.tags, '{}'), coalesce(length(r.notes), 0) > 0
    FROM g
    LEFT JOIN profiles p ON p.id = g.cid
    LEFT JOIN client_records r ON r.provider_id = auth.uid() AND r.client_key = g.k
   ORDER BY coalesce(g.next_booking, g.last_visit) DESC NULLS LAST;
$$;

CREATE OR REPLACE FUNCTION public.admin_set_ban(p_user uuid, p_ban boolean, p_reason text DEFAULT NULL,
                                                p_dispute uuid DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  prof profiles;
  b record;
  n_cancelled int := 0;
  reason text := nullif(trim(coalesce(p_reason, '')), '');
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Only admins can do this'; END IF;
  IF p_user = auth.uid() THEN RAISE EXCEPTION 'You can''t ban yourself'; END IF;
  IF EXISTS (SELECT 1 FROM admins WHERE user_id = p_user) THEN
    RAISE EXCEPTION 'Remove their admin access first';
  END IF;
  SELECT * INTO prof FROM profiles WHERE id = p_user;
  IF NOT FOUND THEN RAISE EXCEPTION 'Account not found'; END IF;
  IF p_ban AND reason IS NULL THEN RAISE EXCEPTION 'Add a reason for the ban'; END IF;

  IF p_ban THEN
    UPDATE profiles SET is_banned = true WHERE id = p_user;
    INSERT INTO profile_private (user_id, banned_at, banned_reason, hidden_before_ban)
    VALUES (p_user, now(), reason, (SELECT coalesce(is_hidden, false) FROM provider_profiles WHERE provider_id = p_user))
    ON CONFLICT (user_id) DO UPDATE SET banned_at = EXCLUDED.banned_at, banned_reason = EXCLUDED.banned_reason,
           hidden_before_ban = EXCLUDED.hidden_before_ban;
    UPDATE provider_profiles SET is_hidden = true WHERE provider_id = p_user;

    -- Block sign-in and end every session (the app also checks on open).
    UPDATE auth.users SET banned_until = '2999-12-31 00:00:00+00' WHERE id = p_user;
    DELETE FROM auth.sessions WHERE user_id = p_user;

    FOR b IN SELECT id, client_id, provider_id FROM bookings
              WHERE (provider_id = p_user OR client_id = p_user)
                AND status IN ('pending', 'confirmed') AND booking_time > now()
    LOOP
      UPDATE bookings SET status = 'cancelled', cancelled_by = 'system', cancelled_at = now(),
             cancel_reason = 'Cancelled by BeauTap: this account was suspended.'
       WHERE id = b.id;
      n_cancelled := n_cancelled + 1;
      INSERT INTO notifications (user_id, type, title, body, reference_id)
      SELECT other, 'booking', 'Booking cancelled by BeauTap',
             'The other person''s account was suspended, so this booking is cancelled. '
             || 'If you paid them anything, contact BeauTap support and we''ll help.', b.id
        FROM (SELECT CASE WHEN b.provider_id = p_user THEN b.client_id ELSE b.provider_id END AS other) o
       WHERE other IS NOT NULL;
    END LOOP;
  ELSE
    UPDATE profiles SET is_banned = false WHERE id = p_user;
    UPDATE provider_profiles
       SET is_hidden = coalesce((SELECT hidden_before_ban FROM profile_private WHERE user_id = p_user), is_hidden)
     WHERE provider_id = p_user;
    UPDATE profile_private SET banned_at = NULL, banned_reason = NULL, hidden_before_ban = NULL WHERE user_id = p_user;
    UPDATE auth.users SET banned_until = NULL WHERE id = p_user;
  END IF;

  IF p_dispute IS NOT NULL THEN
    UPDATE disputes SET status = 'resolved', resolved_by = auth.uid(), resolved_at = now(),
           resolution = coalesce(resolution, 'We looked into your report and suspended the account. Thank you for telling us.')
     WHERE id = p_dispute AND p_ban;
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    SELECT reporter_id, 'dispute', 'Your report was resolved',
           'We looked into your report and suspended the account. Thank you for telling us.', booking_id
      FROM disputes WHERE id = p_dispute AND p_ban;
  END IF;

  RETURN jsonb_build_object('banned', p_ban, 'cancelled', n_cancelled);
END $$;

CREATE OR REPLACE FUNCTION public.products_feed(p_city text DEFAULT NULL::text, p_limit integer DEFAULT 12)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
  SELECT coalesce(jsonb_agg(x ORDER BY x.boosted DESC, x.created_at DESC), '[]'::jsonb) FROM (
    SELECT pr.id, pr.name, pr.price, pr.description, pr.image_url, pr.created_at,
           coalesce(pr.boosted_until > now(), false) AS boosted,
           pr.provider_id, p.full_name AS pro_name, p.avatar_url,
           coalesce(nullif(trim(p.whatsapp_number), ''), public._phone(p.id)) AS contact,
           c.name AS city, pp.area
      FROM products pr
      JOIN provider_profiles pp ON pp.provider_id = pr.provider_id
      JOIN profiles p ON p.id = pr.provider_id
      JOIN cities c ON c.id = pp.city_id
     WHERE pr.is_active AND NOT coalesce(pp.is_hidden, false) AND NOT coalesce(p.is_banned, false)
       AND nullif(trim(pp.area), '') IS NOT NULL
       AND (p_city IS NULL OR p_city = 'All Zimbabwe' OR c.name = p_city)
     ORDER BY coalesce(pr.boosted_until > now(), false) DESC, pr.created_at DESC
     LIMIT greatest(1, least(p_limit, 30))
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public.package_members_for(p_package uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE m record;res jsonb := '[]'::jsonb; r package_periods;
BEGIN
  IF NOT EXISTS (SELECT 1 FROM monthly_packages WHERE id = p_package AND provider_id = auth.uid()) THEN
    RAISE EXCEPTION 'Package not found';
  END IF;
  FOR m IN SELECT pm.*, pr.full_name, pr.avatar_url, public._phone(pr.id) AS phone
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
