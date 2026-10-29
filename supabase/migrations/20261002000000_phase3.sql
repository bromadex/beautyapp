-- Phase 3: stylist tools — manual/walk-in bookings, client records.

-- ───────────────── Manual bookings ─────────────────
-- Bookings a stylist got by phone, WhatsApp or walk-in. The client may not use BeauTap.

ALTER TABLE bookings ALTER COLUMN client_id DROP NOT NULL;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS source text NOT NULL DEFAULT 'app';
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS walkin_name text;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS walkin_phone text;
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_source_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_source_check CHECK (source IN ('app', 'manual'));
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_client_or_walkin;
ALTER TABLE bookings ADD CONSTRAINT bookings_client_or_walkin
  CHECK (client_id IS NOT NULL OR (source = 'manual' AND length(trim(coalesce(walkin_name, ''))) > 0));

-- Stylists' own bookings don't use up the free plan's 5 app bookings.
CREATE OR REPLACE FUNCTION public.free_bookings_used(p_provider uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM bookings
   WHERE provider_id = p_provider
     AND source = 'app'
     AND created_at >= (date_trunc('month', now() AT TIME ZONE 'Africa/Harare') AT TIME ZONE 'Africa/Harare')
     AND NOT (status = 'cancelled' AND cancelled_by = 'client');
$$;

-- The source and walk-in details are set only by create_manual_booking.
CREATE OR REPLACE FUNCTION public.bookings_source_guard() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF public.is_privileged() THEN RETURN NEW; END IF;
  IF TG_OP = 'INSERT' THEN
    NEW.source := 'app'; NEW.walkin_name := NULL; NEW.walkin_phone := NULL;
  ELSE
    NEW.source := OLD.source;
    IF auth.uid() IS DISTINCT FROM OLD.provider_id OR OLD.source <> 'manual' THEN
      NEW.walkin_name := OLD.walkin_name; NEW.walkin_phone := OLD.walkin_phone;
    END IF;
  END IF;
  RETURN NEW;
END $$;
DROP TRIGGER IF EXISTS trg_bookings_source_guard ON bookings;
CREATE TRIGGER trg_bookings_source_guard BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_source_guard();

-- Normalise Zimbabwe numbers to +263… so the same client matches across bookings.
CREATE OR REPLACE FUNCTION public._norm_phone(p text) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN d = '' THEN NULL
    WHEN d LIKE '263%' THEN '+' || d
    WHEN d LIKE '0%' THEN '+263' || substr(d, 2)
    WHEN length(d) = 9 THEN '+263' || d
    ELSE '+' || d END
  FROM (SELECT regexp_replace(coalesce(p, ''), '\D', '', 'g') AS d) x;
$$;

-- Log a booking the stylist took outside the app. Past times are allowed (walk-ins
-- already done); future times must not clash with other bookings.
CREATE OR REPLACE FUNCTION public.create_manual_booking(
  p_service uuid, p_time timestamptz, p_name text, p_phone text DEFAULT NULL,
  p_tier uuid DEFAULT NULL, p_price numeric DEFAULT NULL, p_note text DEFAULT NULL,
  p_client uuid DEFAULT NULL, p_paid boolean DEFAULT false, p_address text DEFAULT NULL)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  uid uuid := auth.uid();
  svc services;
  mins int;
  buf int;
  done boolean := p_time <= now();
  b bookings;
BEGIN
  IF uid IS NULL OR NOT EXISTS (SELECT 1 FROM provider_profiles WHERE provider_id = uid) THEN
    RAISE EXCEPTION 'Only stylists can add bookings';
  END IF;
  SELECT * INTO svc FROM services WHERE id = p_service AND provider_id = uid;
  IF NOT FOUND THEN RAISE EXCEPTION 'Pick one of your services'; END IF;
  IF p_tier IS NOT NULL AND NOT EXISTS (SELECT 1 FROM service_tiers WHERE id = p_tier AND service_id = p_service) THEN
    RAISE EXCEPTION 'Option not available';
  END IF;
  IF p_client IS NULL AND length(trim(coalesce(p_name, ''))) < 2 THEN
    RAISE EXCEPTION 'Enter the client''s name';
  END IF;
  IF p_client IS NOT NULL AND NOT EXISTS (SELECT 1 FROM bookings WHERE client_id = p_client AND provider_id = uid) THEN
    RAISE EXCEPTION 'Client not found';
  END IF;
  IF p_price IS NOT NULL AND (p_price < 0 OR p_price > 10000) THEN RAISE EXCEPTION 'Check the price'; END IF;
  IF p_time < now() - interval '60 days' OR p_time > now() + interval '365 days' THEN
    RAISE EXCEPTION 'Pick a date within the last 60 days or the next year';
  END IF;

  mins := coalesce((SELECT duration_minutes FROM service_tiers WHERE id = p_tier), svc.duration_minutes, 60);
  buf := coalesce((SELECT buffer_minutes FROM provider_profiles WHERE provider_id = uid), 0);
  IF NOT done AND EXISTS (
    SELECT 1 FROM bookings x
     WHERE x.provider_id = uid AND x.status IN ('pending', 'confirmed')
       AND x.booking_time < p_time + make_interval(mins => mins + buf)
       AND x.booking_time + make_interval(mins => public._booking_minutes(x) + buf) > p_time) THEN
    RAISE EXCEPTION 'You already have a booking around that time';
  END IF;

  PERFORM public._bypass();
  INSERT INTO bookings(client_id, provider_id, service_id, tier_id, booking_time, address, status,
                       client_note, source, walkin_name, walkin_phone, agreed_price, negotiation_status,
                       payment_status, payment_method, service_completed_at, total_price)
  VALUES (p_client, uid, p_service, p_tier, p_time, coalesce(nullif(trim(p_address), ''), 'At the salon'),
          CASE WHEN done THEN 'completed' ELSE 'confirmed' END,
          nullif(trim(coalesce(p_note, '')), ''), 'manual',
          CASE WHEN p_client IS NULL THEN initcap(trim(p_name)) END,
          public._norm_phone(p_phone), p_price, CASE WHEN p_price IS NULL THEN 'none' ELSE 'agreed' END,
          CASE WHEN p_paid THEN 'paid' ELSE 'unpaid' END, 'cash',
          CASE WHEN done THEN p_time END, 0)
  RETURNING * INTO b;
  UPDATE bookings SET total_price = public._booking_total(b), deposit_amount = 0 WHERE id = b.id;
  RETURN b.id;
END $$;
REVOKE ALL ON FUNCTION public.create_manual_booking(uuid, timestamptz, text, text, uuid, numeric, text, uuid, boolean, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.create_manual_booking(uuid, timestamptz, text, text, uuid, numeric, text, uuid, boolean, text) TO authenticated;

-- No review nudge for clients who aren't on BeauTap.
CREATE OR REPLACE FUNCTION public.booking_after_update() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE sname text; pname text;
BEGIN
  IF NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed' AND NEW.client_id IS NOT NULL
     AND NOT EXISTS (SELECT 1 FROM reviews WHERE booking_id = NEW.id) THEN
    SELECT full_name INTO pname FROM profiles WHERE id = NEW.provider_id;
    SELECT service_name INTO sname FROM services WHERE id = NEW.service_id;
    INSERT INTO notifications(user_id, type, title, body, reference_id)
    VALUES (NEW.client_id, 'review_request', 'How was your ' || coalesce(sname, 'appointment') || '?',
            'Rate ' || coalesce(pname, 'your stylist') || ' in 10 seconds. It helps other clients choose.',
            NEW.id::text);
  END IF;

  IF (NEW.status = 'cancelled' AND OLD.status IN ('pending', 'confirmed'))
     OR (NEW.booking_time IS DISTINCT FROM OLD.booking_time AND OLD.status IN ('pending', 'confirmed')) THEN
    PERFORM public._notify_waitlist(OLD.provider_id, (OLD.booking_time AT TIME ZONE 'Africa/Harare')::date);
  END IF;
  RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION public.booking_clears_waitlist() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NEW.client_id IS NOT NULL THEN
    DELETE FROM waitlist WHERE client_id = NEW.client_id AND provider_id = NEW.provider_id
       AND day = (NEW.booking_time AT TIME ZONE 'Africa/Harare')::date;
  END IF;
  RETURN NULL;
END $$;

-- ───────────────── Client records ─────────────────
-- One record per client per stylist. Key: the BeauTap user id, else the phone, else the name.

CREATE OR REPLACE FUNCTION public._client_key(b bookings) RETURNS text
LANGUAGE sql IMMUTABLE AS $$
  SELECT coalesce(b.client_id::text, 'tel:' || b.walkin_phone, 'name:' || lower(trim(b.walkin_name)));
$$;

CREATE TABLE IF NOT EXISTS client_records (
  provider_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  client_key text NOT NULL,
  tags text[] NOT NULL DEFAULT '{}',
  notes text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (provider_id, client_key),
  CHECK (cardinality(tags) <= 12),
  CHECK (length(coalesce(notes, '')) <= 4000)
);
ALTER TABLE client_records ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Stylist owns client records" ON client_records;
CREATE POLICY "Stylist owns client records" ON client_records FOR ALL
  USING (provider_id = auth.uid()) WITH CHECK (provider_id = auth.uid());

-- The stylist's client list with visits and spend.
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
  SELECT g.k, g.cid, coalesce(p.full_name, g.wname, 'Client'), coalesce(g.wphone, p.phone),
         g.visits, g.spent, g.last_visit, g.next_booking, g.no_shows,
         coalesce(r.tags, '{}'), coalesce(length(r.notes), 0) > 0
    FROM g
    LEFT JOIN profiles p ON p.id = g.cid
    LEFT JOIN client_records r ON r.provider_id = auth.uid() AND r.client_key = g.k
   ORDER BY coalesce(g.next_booking, g.last_visit) DESC NULLS LAST;
$$;
REVOKE ALL ON FUNCTION public.my_clients() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.my_clients() TO authenticated;

-- One client's bookings with this stylist.
CREATE OR REPLACE FUNCTION public.client_history(p_key text)
RETURNS TABLE(id uuid, booking_time timestamptz, status text, total_price numeric, payment_status text,
              source text, ref text, service_name text, no_show boolean)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT x.id, x.booking_time, x.status, x.total_price, x.payment_status, x.source, x.ref,
         coalesce(t.name || ' · ', '') || coalesce(s.service_name, 'Service'), x.no_show_by = 'client'
    FROM bookings x
    LEFT JOIN services s ON s.id = x.service_id
    LEFT JOIN service_tiers t ON t.id = x.tier_id
   WHERE x.provider_id = auth.uid() AND public._client_key(x) = p_key
   ORDER BY x.booking_time DESC LIMIT 200;
$$;
REVOKE ALL ON FUNCTION public.client_history(text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.client_history(text) TO authenticated;

-- Walk-in clients have no account: skip notifications addressed to nobody.
CREATE OR REPLACE FUNCTION public.notifications_drop_orphans() RETURNS trigger
LANGUAGE plpgsql AS $$ BEGIN IF NEW.user_id IS NULL THEN RETURN NULL; END IF; RETURN NEW; END $$;
DROP TRIGGER IF EXISTS trg_notifications_drop_orphans ON notifications;
CREATE TRIGGER trg_notifications_drop_orphans BEFORE INSERT ON notifications
  FOR EACH ROW EXECUTE FUNCTION public.notifications_drop_orphans();

-- A walk-in booking has no client_id; NOT IN (NULL, x) would let anyone through.
CREATE OR REPLACE FUNCTION public.cancel_booking(p_booking_id uuid, p_reason text DEFAULT NULL::text)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'This booking can no longer be cancelled';
  END IF;
  by_client := auth.uid() = b.client_id;

  IF by_client AND b.status = 'confirmed' THEN
    SELECT * INTO pol FROM cancellation_policies WHERE provider_id = b.provider_id;
    IF FOUND AND b.booking_time - now() < make_interval(hours => pol.free_cancel_hours) THEN
      fee := round(b.total_price * pol.late_cancel_fee_percent / 100.0, 2);
    END IF;
  END IF;

  PERFORM public._bypass();
  UPDATE bookings SET status = 'cancelled',
         cancelled_by = CASE WHEN by_client THEN 'client' ELSE 'provider' END,
         cancelled_at = now(), cancel_reason = nullif(trim(p_reason), ''),
         cancellation_fee = fee
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_client THEN b.provider_id ELSE b.client_id END, 'booking',
          'Booking Cancelled',
          CASE WHEN by_client THEN 'The client cancelled their booking.' ELSE 'Your stylist cancelled the booking.' END
          || coalesce(' Reason: ' || nullif(trim(p_reason), ''), '')
          || CASE WHEN fee > 0 THEN format(' Late cancellation fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$function$;
CREATE OR REPLACE FUNCTION public.mark_no_show(p_booking_id uuid)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; pol cancellation_policies; fee numeric := 0; by_prov boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status <> 'confirmed' THEN RAISE EXCEPTION 'Only confirmed bookings can be marked as a no-show'; END IF;
  IF b.booking_time > now() THEN RAISE EXCEPTION 'You can only report a no-show after the booking time'; END IF;
  by_prov := auth.uid() = b.provider_id;

  IF by_prov THEN
    SELECT * INTO pol FROM cancellation_policies WHERE provider_id = b.provider_id;
    IF FOUND THEN fee := round(b.total_price * pol.no_show_fee_percent / 100.0, 2); END IF;
  END IF;

  PERFORM public._bypass();
  UPDATE bookings SET status = 'cancelled', cancelled_at = now(),
         cancelled_by = CASE WHEN by_prov THEN 'client' ELSE 'provider' END,
         no_show_by = CASE WHEN by_prov THEN 'client' ELSE 'provider' END,
         no_show_at = now(), cancellation_fee = fee,
         cancel_reason = CASE WHEN by_prov THEN 'Client did not show up' ELSE 'Stylist did not show up' END
   WHERE id = p_booking_id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_prov THEN b.client_id ELSE b.provider_id END, 'booking', 'Marked as No-Show',
          CASE WHEN by_prov THEN 'Your stylist reported that you missed your appointment.'
               ELSE 'The client reported that you did not arrive for the appointment.' END
          || CASE WHEN fee > 0 THEN format(' No-show fee: $%s.', fee) ELSE '' END,
          p_booking_id::text);
  RETURN fee;
END;
$function$;
CREATE OR REPLACE FUNCTION public.reschedule_booking(p_booking_id uuid, p_new_time timestamp with time zone)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE b bookings; msg text; by_client boolean;
BEGIN
  SELECT * INTO b FROM bookings WHERE id = p_booking_id FOR UPDATE;
  IF NOT FOUND OR (auth.uid() IS DISTINCT FROM b.provider_id AND auth.uid() IS DISTINCT FROM b.client_id) THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
  IF b.status NOT IN ('pending', 'confirmed') THEN
    RAISE EXCEPTION 'Only upcoming bookings can be moved';
  END IF;
  by_client := auth.uid() = b.client_id;
  msg := public.check_slot(b.provider_id, p_new_time, public._booking_minutes(b), b.id);
  IF msg IS NOT NULL THEN RAISE EXCEPTION '%', msg; END IF;

  PERFORM public._bypass();
  UPDATE bookings SET booking_time = p_new_time, reminder_sent = false, rescheduled_at = now(),
         status = CASE WHEN by_client THEN 'pending' ELSE status END
   WHERE id = b.id;

  INSERT INTO notifications (user_id, type, title, body, reference_id)
  VALUES (CASE WHEN by_client THEN b.provider_id ELSE b.client_id END, 'booking', 'Booking Moved',
          CASE WHEN by_client THEN 'Your client moved their booking to '
               ELSE 'Your stylist moved your booking to ' END
          || to_char(p_new_time AT TIME ZONE 'Africa/Harare', 'Dy DD Mon, HH24:MI')
          || CASE WHEN by_client THEN '. Please confirm the new time.' ELSE '.' END,
          b.id::text);
END;
$function$;
