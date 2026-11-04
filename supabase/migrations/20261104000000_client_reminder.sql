-- Clients choose when they are reminded about a booking: 30 minutes,
-- 1 hour or 1 day before, or not at all (0). Pros keep the 1-hour reminder
-- (reminder_sent); the client's reminder is tracked separately.

ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_reminder_minutes smallint NOT NULL DEFAULT 60;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS client_reminder_sent boolean NOT NULL DEFAULT false;
ALTER TABLE bookings DROP CONSTRAINT IF EXISTS bookings_client_reminder_choice;
ALTER TABLE bookings ADD CONSTRAINT bookings_client_reminder_choice
  CHECK (client_reminder_minutes IN (0, 30, 60, 1440));

-- Bookings already reminded under the old 1-hour rule stay reminded.
UPDATE bookings SET client_reminder_sent = true WHERE reminder_sent AND NOT client_reminder_sent;

-- Only the client may change their reminder, and the "sent" flag is set by
-- the server alone. A new time means a new reminder.
CREATE OR REPLACE FUNCTION public.bookings_client_reminder_guard() RETURNS trigger
LANGUAGE plpgsql SET search_path = public AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.client_reminder_sent := false;
    RETURN NEW;
  END IF;
  IF auth.uid() IS NOT NULL THEN
    NEW.client_reminder_sent := OLD.client_reminder_sent;
    IF auth.uid() IS DISTINCT FROM OLD.client_id THEN
      NEW.client_reminder_minutes := OLD.client_reminder_minutes;
    END IF;
  END IF;
  IF NEW.booking_time IS DISTINCT FROM OLD.booking_time THEN
    NEW.client_reminder_sent := false;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_bookings_zz_client_reminder ON bookings;
CREATE TRIGGER trg_bookings_zz_client_reminder BEFORE INSERT OR UPDATE ON bookings
  FOR EACH ROW EXECUTE FUNCTION public.bookings_client_reminder_guard();

-- The client's app sets the reminder through this, so it works whatever
-- other booking columns the guard protects.
CREATE OR REPLACE FUNCTION public.set_booking_reminder(p_booking uuid, p_minutes int) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF p_minutes NOT IN (0, 30, 60, 1440) THEN
    RAISE EXCEPTION 'Choose 30 minutes, 1 hour, 1 day or no reminder';
  END IF;
  UPDATE bookings SET client_reminder_minutes = p_minutes
   WHERE id = p_booking AND client_id = auth.uid();
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Booking not found';
  END IF;
END $$;
GRANT EXECUTE ON FUNCTION public.set_booking_reminder(uuid, int) TO authenticated;
