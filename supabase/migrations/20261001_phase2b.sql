-- Phase 2b: better reviews, coverage requests, waitlist.

-- ───────────────────────── Reviews ─────────────────────────

ALTER TABLE reviews ADD COLUMN IF NOT EXISTS is_hidden boolean NOT NULL DEFAULT false;
ALTER TABLE reviews ADD COLUMN IF NOT EXISTS helpful_count integer NOT NULL DEFAULT 0;

-- Hidden reviews stay visible to the two people involved and to admins.
DROP POLICY IF EXISTS "Anyone can read reviews" ON reviews;
CREATE POLICY "Anyone can read reviews" ON reviews FOR SELECT
  USING (NOT is_hidden OR client_id = auth.uid() OR provider_id = auth.uid() OR public.is_admin());

-- Only the reply may be edited by users; hiding and counts are server-owned.
CREATE OR REPLACE FUNCTION public.reviews_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'UPDATE' THEN
    IF NEW.rating IS DISTINCT FROM OLD.rating OR NEW.comment IS DISTINCT FROM OLD.comment
       OR NEW.client_id IS DISTINCT FROM OLD.client_id OR NEW.provider_id IS DISTINCT FROM OLD.provider_id
       OR NEW.booking_id IS DISTINCT FROM OLD.booking_id
       OR NEW.after_service_image_url IS DISTINCT FROM OLD.after_service_image_url
       OR NEW.is_hidden IS DISTINCT FROM OLD.is_hidden
       OR NEW.helpful_count IS DISTINCT FROM OLD.helpful_count THEN
      RAISE EXCEPTION 'Only the reply can be changed';
    END IF;
    NEW.provider_reply_at := now();
  ELSE
    NEW.provider_reply := NULL;
    NEW.provider_reply_at := NULL;
    NEW.is_hidden := false;
    NEW.helpful_count := 0;
    IF NEW.provider_id IS DISTINCT FROM (SELECT provider_id FROM bookings WHERE id = NEW.booking_id) THEN
      RAISE EXCEPTION 'Review does not match booking';
    END IF;
  END IF;
  RETURN NEW;
END $$;

-- Ratings ignore hidden reviews and refresh when a review is hidden or restored.
CREATE OR REPLACE FUNCTION public.update_provider_rating() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE pid uuid := coalesce(NEW.provider_id, OLD.provider_id);
BEGIN
  PERFORM public._bypass();
  UPDATE provider_profiles SET
    average_rating = coalesce((SELECT round(avg(rating)::numeric, 2) FROM reviews
                                WHERE provider_id = pid AND NOT is_hidden), 0),
    total_reviews  = (SELECT count(*) FROM reviews WHERE provider_id = pid AND NOT is_hidden)
  WHERE provider_id = pid;
  RETURN NULL;
END $$;

DROP TRIGGER IF EXISTS on_review_hidden ON reviews;
CREATE TRIGGER on_review_hidden AFTER UPDATE OF is_hidden OR DELETE ON reviews
  FOR EACH ROW EXECUTE FUNCTION public.update_provider_rating();

CREATE TABLE IF NOT EXISTS review_votes (
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (review_id, user_id)
);
ALTER TABLE review_votes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Own votes" ON review_votes;
CREATE POLICY "Own votes" ON review_votes FOR SELECT USING (user_id = auth.uid());

CREATE TABLE IF NOT EXISTS review_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL REFERENCES reviews(id) ON DELETE CASCADE,
  reporter_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reason text NOT NULL CHECK (length(reason) BETWEEN 3 AND 500),
  status text NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'hidden', 'kept')),
  created_at timestamptz NOT NULL DEFAULT now(),
  resolved_at timestamptz,
  UNIQUE (review_id, reporter_id)
);
ALTER TABLE review_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read reports" ON review_reports;
CREATE POLICY "Admins read reports" ON review_reports FOR SELECT
  USING (public.is_admin() OR reporter_id = auth.uid());

-- Toggle "helpful". Returns the new count and whether the caller now has a vote.
CREATE OR REPLACE FUNCTION public.toggle_review_helpful(p_review uuid) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); r reviews; voted boolean;
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Sign in to vote'; END IF;
  SELECT * INTO r FROM reviews WHERE id = p_review AND NOT is_hidden;
  IF NOT FOUND THEN RAISE EXCEPTION 'Review not found'; END IF;
  IF uid IN (r.client_id, r.provider_id) THEN RAISE EXCEPTION 'You can''t vote on this review'; END IF;
  DELETE FROM review_votes WHERE review_id = p_review AND user_id = uid;
  voted := NOT FOUND;
  IF voted THEN INSERT INTO review_votes(review_id, user_id) VALUES (p_review, uid); END IF;
  PERFORM public._bypass();
  UPDATE reviews SET helpful_count = (SELECT count(*) FROM review_votes WHERE review_id = p_review)
   WHERE id = p_review RETURNING helpful_count INTO r.helpful_count;
  RETURN jsonb_build_object('count', r.helpful_count, 'voted', voted);
END $$;

CREATE OR REPLACE FUNCTION public.report_review(p_review uuid, p_reason text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Sign in to report'; END IF;
  IF NOT EXISTS (SELECT 1 FROM reviews WHERE id = p_review) THEN RAISE EXCEPTION 'Review not found'; END IF;
  IF length(trim(coalesce(p_reason, ''))) < 3 THEN RAISE EXCEPTION 'Tell us what''s wrong with this review'; END IF;
  INSERT INTO review_reports(review_id, reporter_id, reason)
  VALUES (p_review, uid, left(trim(p_reason), 500))
  ON CONFLICT (review_id, reporter_id) DO UPDATE SET reason = EXCLUDED.reason, status = 'open', resolved_at = NULL;
END $$;

-- Admin decision: hide the review (true) or keep it (false). Closes its open reports.
CREATE OR REPLACE FUNCTION public.moderate_review(p_review uuid, p_hide boolean) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admins only'; END IF;
  PERFORM public._bypass();
  UPDATE reviews SET is_hidden = p_hide WHERE id = p_review;
  UPDATE review_reports SET status = CASE WHEN p_hide THEN 'hidden' ELSE 'kept' END, resolved_at = now()
   WHERE review_id = p_review AND status = 'open';
END $$;

REVOKE ALL ON FUNCTION public.toggle_review_helpful(uuid), public.report_review(uuid, text),
  public.moderate_review(uuid, boolean) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.toggle_review_helpful(uuid), public.report_review(uuid, text),
  public.moderate_review(uuid, boolean) TO authenticated;

-- ─────────────────── Notifications from the server ───────────────────

-- Server-side notifications (review nudges, waitlist alerts) also go out as pushes.
DROP TRIGGER IF EXISTS trg_push_notifications ON notifications;
CREATE TRIGGER trg_push_notifications AFTER INSERT ON notifications
  FOR EACH ROW WHEN (NEW.type IN ('review_request', 'waitlist'))
  EXECUTE FUNCTION public.beautap_push_dispatch();

-- Ask the client for a review once the appointment is completed.
CREATE OR REPLACE FUNCTION public.booking_after_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sname text; pname text;
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed'
     AND NOT EXISTS (SELECT 1 FROM reviews WHERE booking_id = NEW.id) THEN
    SELECT full_name INTO pname FROM profiles WHERE id = NEW.provider_id;
    SELECT service_name INTO sname FROM services WHERE id = NEW.service_id;
    INSERT INTO notifications(user_id, type, title, body, reference_id)
    VALUES (NEW.client_id, 'review_request', 'How was your ' || coalesce(sname, 'appointment') || '?',
            'Rate ' || coalesce(pname, 'your stylist') || ' in 10 seconds. It helps other clients choose.',
            NEW.id::text);
  END IF;

  -- A slot may have opened: cancelled, or moved to another time.
  IF (NEW.status = 'cancelled' AND OLD.status IN ('pending', 'confirmed'))
     OR (NEW.booking_time IS DISTINCT FROM OLD.booking_time AND OLD.status IN ('pending', 'confirmed')) THEN
    PERFORM public._notify_waitlist(OLD.provider_id, (OLD.booking_time AT TIME ZONE 'Africa/Harare')::date);
  END IF;
  RETURN NULL;
END $$;

-- ───────────────────────── Waitlist ─────────────────────────

CREATE TABLE IF NOT EXISTS waitlist (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL DEFAULT auth.uid() REFERENCES auth.users(id) ON DELETE CASCADE,
  provider_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  service_id uuid REFERENCES services(id) ON DELETE SET NULL,
  day date NOT NULL,
  minutes integer NOT NULL DEFAULT 60 CHECK (minutes BETWEEN 5 AND 720),
  created_at timestamptz NOT NULL DEFAULT now(),
  notified_at timestamptz,
  UNIQUE (client_id, provider_id, day)
);
ALTER TABLE waitlist ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Client reads own waitlist" ON waitlist;
CREATE POLICY "Client reads own waitlist" ON waitlist FOR SELECT
  USING (client_id = auth.uid() OR provider_id = auth.uid());
DROP POLICY IF EXISTS "Client leaves waitlist" ON waitlist;
CREATE POLICY "Client leaves waitlist" ON waitlist FOR DELETE USING (client_id = auth.uid());

CREATE OR REPLACE FUNCTION public.join_waitlist(p_provider uuid, p_day date, p_minutes integer,
                                                p_service uuid DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid();
BEGIN
  IF uid IS NULL THEN RAISE EXCEPTION 'Sign in to join the waitlist'; END IF;
  IF uid = p_provider THEN RAISE EXCEPTION 'You can''t join your own waitlist'; END IF;
  IF p_day < (now() AT TIME ZONE 'Africa/Harare')::date OR p_day > (now() AT TIME ZONE 'Africa/Harare')::date + 120 THEN
    RAISE EXCEPTION 'Pick a date in the next few months';
  END IF;
  IF (SELECT count(*) FROM waitlist WHERE client_id = uid AND notified_at IS NULL
        AND day >= (now() AT TIME ZONE 'Africa/Harare')::date) >= 10 THEN
    RAISE EXCEPTION 'You''re on 10 waitlists already. Leave one first.';
  END IF;
  INSERT INTO waitlist(client_id, provider_id, service_id, day, minutes)
  VALUES (uid, p_provider, p_service, p_day, greatest(5, least(coalesce(p_minutes, 60), 720)))
  ON CONFLICT (client_id, provider_id, day)
  DO UPDATE SET minutes = EXCLUDED.minutes, service_id = EXCLUDED.service_id, notified_at = NULL, created_at = now();
END $$;

-- Tell waiting clients about a day that now has a time that fits them.
CREATE OR REPLACE FUNCTION public._notify_waitlist(p_provider uuid, p_day date) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE w record; pname text;
BEGIN
  IF p_day < (now() AT TIME ZONE 'Africa/Harare')::date THEN RETURN; END IF;
  SELECT full_name INTO pname FROM profiles WHERE id = p_provider;
  FOR w IN SELECT * FROM waitlist
            WHERE provider_id = p_provider AND day = p_day AND notified_at IS NULL
            ORDER BY created_at LOOP
    IF EXISTS (SELECT 1 FROM public.available_slots(p_provider, p_day, w.minutes)) THEN
      INSERT INTO notifications(user_id, type, title, body, reference_id)
      VALUES (w.client_id, 'waitlist', 'A time just opened',
              coalesce(pname, 'Your stylist') || ' has a free time on ' || to_char(p_day, 'Dy DD Mon')
                || '. Book it before someone else does.',
              p_provider::text || '|' || coalesce(w.service_id::text, ''));
      UPDATE waitlist SET notified_at = now() WHERE id = w.id;
    END IF;
  END LOOP;
END $$;

REVOKE ALL ON FUNCTION public.join_waitlist(uuid, date, integer, uuid), public._notify_waitlist(uuid, date) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.join_waitlist(uuid, date, integer, uuid) TO authenticated;

DROP TRIGGER IF EXISTS trg_booking_after_update ON bookings;
CREATE TRIGGER trg_booking_after_update AFTER UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.booking_after_update();

-- A client who books that stylist on that day no longer needs the alert.
CREATE OR REPLACE FUNCTION public.booking_clears_waitlist() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  DELETE FROM waitlist WHERE client_id = NEW.client_id AND provider_id = NEW.provider_id
     AND day = (NEW.booking_time AT TIME ZONE 'Africa/Harare')::date;
  RETURN NULL;
END $$;
DROP TRIGGER IF EXISTS trg_booking_clears_waitlist ON bookings;
CREATE TRIGGER trg_booking_clears_waitlist AFTER INSERT ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.booking_clears_waitlist();

-- ───────────────────── Coverage requests ─────────────────────

CREATE TABLE IF NOT EXISTS area_requests (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  city text NOT NULL CHECK (length(city) BETWEEN 2 AND 60),
  category text CHECK (category IS NULL OR length(category) <= 60),
  created_at timestamptz NOT NULL DEFAULT now()
);
ALTER TABLE area_requests ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins read area requests" ON area_requests;
CREATE POLICY "Admins read area requests" ON area_requests FOR SELECT USING (public.is_admin());

-- Anyone may ask; signed-in users count once per city and service per week.
CREATE OR REPLACE FUNCTION public.request_area(p_city text, p_category text DEFAULT NULL) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE uid uuid := auth.uid(); c text := initcap(trim(coalesce(p_city, ''))); cat text := nullif(trim(coalesce(p_category, '')), '');
BEGIN
  IF length(c) < 2 OR length(c) > 60 THEN RAISE EXCEPTION 'Enter your town or suburb'; END IF;
  IF uid IS NOT NULL AND EXISTS (SELECT 1 FROM area_requests WHERE user_id = uid AND lower(city) = lower(c)
        AND category IS NOT DISTINCT FROM cat AND created_at > now() - interval '7 days') THEN
    RETURN;
  END IF;
  INSERT INTO area_requests(user_id, city, category) VALUES (uid, c, left(cat, 60));
END $$;

CREATE OR REPLACE FUNCTION public.area_demand(p_days integer DEFAULT 90)
RETURNS TABLE(city text, requests bigint, people bigint, top_category text, last_at timestamptz)
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'Admins only'; END IF;
  RETURN QUERY
  SELECT a.city, count(*), count(DISTINCT a.user_id),
         mode() WITHIN GROUP (ORDER BY a.category), max(a.created_at)
    FROM area_requests a
   WHERE a.created_at > now() - make_interval(days => p_days)
   GROUP BY a.city
   ORDER BY count(*) DESC, max(a.created_at) DESC
   LIMIT 100;
END $$;

REVOKE ALL ON FUNCTION public.request_area(text, text), public.area_demand(integer) FROM public;
GRANT EXECUTE ON FUNCTION public.request_area(text, text) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.area_demand(integer) TO authenticated;
