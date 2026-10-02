-- Bans that actually stop someone: they can't sign in, existing sessions end,
-- a banned pro disappears from Browse and the product feed, nobody can book
-- them, and their upcoming bookings are cancelled with a note to the client.

ALTER TABLE profiles
  ADD COLUMN IF NOT EXISTS banned_at timestamptz,
  ADD COLUMN IF NOT EXISTS banned_reason text,
  ADD COLUMN IF NOT EXISTS hidden_before_ban boolean;

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
    UPDATE profiles SET is_banned = true, banned_at = now(), banned_reason = reason,
           hidden_before_ban = (SELECT coalesce(is_hidden, false) FROM provider_profiles WHERE provider_id = p_user)
     WHERE id = p_user;
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
    UPDATE profiles SET is_banned = false, banned_at = NULL, banned_reason = NULL, hidden_before_ban = NULL
     WHERE id = p_user;
    UPDATE provider_profiles SET is_hidden = coalesce(prof.hidden_before_ban, is_hidden) WHERE provider_id = p_user;
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
REVOKE ALL ON FUNCTION public.admin_set_ban(uuid, boolean, text, uuid) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_ban(uuid, boolean, text, uuid) TO authenticated;

-- No new bookings with a banned account (walk-ins are the pro's own).
CREATE OR REPLACE FUNCTION public.bookings_ban_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM profiles WHERE id IN (NEW.provider_id, NEW.client_id) AND is_banned) THEN
    RAISE EXCEPTION 'This account isn''t available for bookings.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bookings_ban_guard ON bookings;
CREATE TRIGGER trg_bookings_ban_guard BEFORE INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_ban_guard();

-- Banned accounts can't send messages either.
CREATE OR REPLACE FUNCTION public.messages_ban_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM profiles WHERE id = NEW.sender_id AND is_banned) THEN
    RAISE EXCEPTION 'This account has been suspended.';
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_messages_ban_guard ON messages;
CREATE TRIGGER trg_messages_ban_guard BEFORE INSERT ON messages
  FOR EACH ROW EXECUTE FUNCTION public.messages_ban_guard();

-- Product feed skips banned pros.
CREATE OR REPLACE FUNCTION public.products_feed(p_city text DEFAULT NULL::text, p_limit integer DEFAULT 12)
 RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public' AS $function$
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
     WHERE pr.is_active AND NOT coalesce(pp.is_hidden, false) AND NOT coalesce(p.is_banned, false)
       AND nullif(trim(pp.area), '') IS NOT NULL
       AND (p_city IS NULL OR p_city = 'All Zimbabwe' OR c.name = p_city)
     ORDER BY coalesce(pr.boosted_until > now(), false) DESC, pr.created_at DESC
     LIMIT greatest(1, least(p_limit, 30))
  ) x;
$function$;

-- A banned pro stays hidden even if a plan payment would normally unhide them.
CREATE OR REPLACE FUNCTION public.provider_ban_hidden() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT coalesce(NEW.is_hidden, false)
     AND EXISTS (SELECT 1 FROM profiles WHERE id = NEW.provider_id AND is_banned) THEN
    NEW.is_hidden := true;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_provider_ban_hidden ON provider_profiles;
CREATE TRIGGER trg_provider_ban_hidden BEFORE INSERT OR UPDATE ON provider_profiles
  FOR EACH ROW EXECUTE FUNCTION public.provider_ban_hidden();

-- Accounts banned before this change: apply the full ban now.
UPDATE provider_profiles SET is_hidden = true
 WHERE provider_id IN (SELECT id FROM profiles WHERE is_banned);
UPDATE auth.users SET banned_until = '2999-12-31 00:00:00+00'
 WHERE id IN (SELECT id FROM profiles WHERE is_banned) AND banned_until IS NULL;
