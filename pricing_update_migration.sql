-- ============================================================
-- Pricing Update: $3 first month, $5/month after, 0% commission
-- Run this in the Supabase Dashboard SQL editor (project suxohsmcgjzzllmyesgt)
-- AFTER stage20/21 migrations. Safe to run more than once.
-- ============================================================

-- 1) Providers keep 100% of booking payments — no commission split
ALTER TABLE payments DROP COLUMN IF EXISTS platform_fee;
ALTER TABLE payments DROP COLUMN IF EXISTS provider_earnings;

-- 2) First-booking-free is replaced by the $3 activation model:
--    accepting any booking now requires an active subscription.
DROP TRIGGER IF EXISTS trg_mark_first_booking_used ON bookings;
DROP FUNCTION IF EXISTS mark_first_booking_used();

-- 3) Subscription plans become 'activation' ($3, first month) and
--    'monthly' ($5). The old 'tier' concept is not used by the new model,
--    so nothing is needed here even if the tier column never existed.

-- 4) Allow 'cancelled' as a subscription status (cancel anytime →
--    profile hidden, reactivate later for $3).
--    Only needed if your status column has a CHECK constraint; if this
--    errors with "constraint does not exist", ignore it.
DO $$
BEGIN
  BEGIN
    ALTER TABLE subscriptions DROP CONSTRAINT IF EXISTS subscriptions_status_check;
  EXCEPTION WHEN others THEN NULL;
  END;
END $$;
