-- ============================================================
-- Stage 21: Subscription Revamp — First Booking Free
-- Run this in the Supabase Dashboard SQL editor (project suxohsmcgjzzllmyesgt)
-- Safe to run more than once.
-- ============================================================

-- 1) Tier on subscriptions: 'active' ($10/mo) or 'featured' ($25/mo).
--    Providers with no subscription row are on the free 'New' tier.
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS tier TEXT DEFAULT 'active'
  CHECK (tier IN ('active', 'featured'));

-- 2) First-booking-free gate + service radius (Featured "area" definition)
ALTER TABLE provider_profiles
  ADD COLUMN IF NOT EXISTS first_booking_used BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS service_radius_km NUMERIC DEFAULT 10;

-- Grandfather existing providers who already completed bookings
UPDATE provider_profiles pp
SET first_booking_used = true
WHERE EXISTS (
  SELECT 1 FROM bookings b
  WHERE b.provider_id = pp.provider_id AND b.status = 'completed'
);

-- 3) Auto-set first_booking_used when a booking completes
CREATE OR REPLACE FUNCTION mark_first_booking_used()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.status = 'completed' AND (OLD.status IS DISTINCT FROM 'completed') THEN
    UPDATE provider_profiles
    SET first_booking_used = true
    WHERE provider_id = NEW.provider_id AND first_booking_used = false;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_mark_first_booking_used ON bookings;
CREATE TRIGGER trg_mark_first_booking_used
  AFTER UPDATE ON bookings
  FOR EACH ROW
  EXECUTE FUNCTION mark_first_booking_used();

-- 4) Featured waitlist (max 3 Featured providers per area)
CREATE TABLE IF NOT EXISTS featured_waitlist (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  provider_id UUID REFERENCES profiles(id) ON DELETE CASCADE,
  requested_at TIMESTAMPTZ DEFAULT now(),
  notified_at TIMESTAMPTZ,
  status TEXT DEFAULT 'waiting' CHECK (status IN ('waiting', 'notified', 'expired', 'activated')),
  UNIQUE(provider_id)
);

ALTER TABLE featured_waitlist ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Providers manage own waitlist entry" ON featured_waitlist;
CREATE POLICY "Providers manage own waitlist entry" ON featured_waitlist
  FOR ALL USING (auth.uid() = provider_id) WITH CHECK (auth.uid() = provider_id);

DROP POLICY IF EXISTS "Waitlist readable by authenticated" ON featured_waitlist;
CREATE POLICY "Waitlist readable by authenticated" ON featured_waitlist
  FOR SELECT USING (auth.role() = 'authenticated');
