-- Deposit time limit: clients get 2 hours to send the deposit (less if the
-- appointment is sooner). If it hasn't arrived and no "I've paid" claim is
-- waiting, the booking is released so the slot opens up again.

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS deposit_due_at timestamptz;

ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_cancelled_by_check;
ALTER TABLE bookings ADD CONSTRAINT bookings_cancelled_by_check
  CHECK (cancelled_by IN ('client', 'provider', 'system'));

-- Released bookings don't use up a pro's free monthly bookings.
CREATE OR REPLACE FUNCTION public.free_bookings_used(p_provider uuid) RETURNS integer
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT count(*)::int FROM bookings
   WHERE provider_id = p_provider
     AND created_at >= (date_trunc('month', now() AT TIME ZONE 'Africa/Harare') AT TIME ZONE 'Africa/Harare')
     AND NOT (status = 'cancelled' AND cancelled_by IN ('client', 'system'));
$$;

CREATE OR REPLACE FUNCTION public.bookings_deposit_due() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    IF coalesce(NEW.deposit_amount, 0) > 0 AND NOT coalesce(NEW.deposit_paid, false)
       AND coalesce(NEW.source, 'app') <> 'manual' THEN
      NEW.deposit_due_at := least(now() + interval '2 hours',
                                  greatest(NEW.booking_time - interval '30 minutes', now() + interval '15 minutes'));
    ELSE
      NEW.deposit_due_at := NULL;
    END IF;
    RETURN NEW;
  END IF;

  IF NOT public.is_privileged() THEN
    NEW.deposit_due_at := OLD.deposit_due_at;
  END IF;
  IF NEW.deposit_paid OR coalesce(NEW.deposit_amount, 0) = 0 OR NEW.status NOT IN ('pending', 'confirmed') THEN
    NEW.deposit_due_at := NULL;
  END IF;
  RETURN NEW;
END $$;

-- Runs after trg_bookings_guard (triggers fire in name order), so the
-- deposit amount is already worked out.
DROP TRIGGER IF EXISTS trg_bookings_zz_deposit_due ON bookings;
CREATE TRIGGER trg_bookings_zz_deposit_due BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_deposit_due();

CREATE OR REPLACE FUNCTION public.release_unpaid_deposits() RETURNS integer
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE b record; n int := 0; when_txt text;
BEGIN
  PERFORM public._bypass();
  FOR b IN
    SELECT bk.id, bk.client_id, bk.provider_id, bk.booking_time, s.service_name,
           coalesce(nullif(trim(c.full_name), ''), 'A client') AS client_name,
           coalesce(nullif(trim(p.full_name), ''), 'the pro') AS pro_name
      FROM bookings bk
      LEFT JOIN services s ON s.id = bk.service_id
      LEFT JOIN profiles c ON c.id = bk.client_id
      LEFT JOIN profiles p ON p.id = bk.provider_id
     WHERE bk.status IN ('pending', 'confirmed')
       AND bk.deposit_due_at IS NOT NULL AND bk.deposit_due_at < now()
       AND NOT bk.deposit_paid AND bk.deposit_amount > 0
       AND NOT EXISTS (SELECT 1 FROM pro_payments pp WHERE pp.booking_id = bk.id AND pp.status = 'claimed')
     FOR UPDATE OF bk SKIP LOCKED
  LOOP
    UPDATE bookings SET status = 'cancelled', cancelled_by = 'system', cancelled_at = now(),
                        cancel_reason = 'Deposit not paid in time', deposit_due_at = NULL
     WHERE id = b.id;
    when_txt := to_char(b.booking_time AT TIME ZONE 'Africa/Harare', 'Dy DD Mon, HH24:MI');
    IF b.client_id IS NOT NULL THEN
      INSERT INTO notifications (user_id, type, title, body, reference_id)
      VALUES (b.client_id, 'booking_status', 'Booking released',
              'Your deposit for ' || coalesce(b.service_name, 'your booking') || ' on ' || when_txt
              || ' didn''t arrive in time, so the slot was released. You can book again.', b.id::text);
    END IF;
    INSERT INTO notifications (user_id, type, title, body, reference_id)
    VALUES (b.provider_id, 'booking_status', 'Slot released',
            b.client_name || '''s booking on ' || when_txt || ' was released because the deposit wasn''t paid.',
            b.id::text);
    n := n + 1;
  END LOOP;
  RETURN n;
END $$;

REVOKE ALL ON FUNCTION public.release_unpaid_deposits() FROM public, anon, authenticated;
REVOKE ALL ON FUNCTION public.bookings_deposit_due() FROM public, anon, authenticated;

-- Every 5 minutes.
SELECT cron.unschedule('beautap-release-deposits')
 WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'beautap-release-deposits');
SELECT cron.schedule('beautap-release-deposits', '*/5 * * * *', 'SELECT public.release_unpaid_deposits()');
