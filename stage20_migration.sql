-- ============================================================
-- Stage 20: Real Payments — Paynow Zimbabwe
-- Run this in the Supabase Dashboard SQL editor (project suxohsmcgjzzllmyesgt)
-- Safe to run more than once.
-- ============================================================

ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS gateway TEXT DEFAULT 'paynow',
  ADD COLUMN IF NOT EXISTS gateway_ref TEXT,
  ADD COLUMN IF NOT EXISTS webhook_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD',
  ADD COLUMN IF NOT EXISTS purpose TEXT DEFAULT 'booking'
    CHECK (purpose IN ('booking', 'activation', 'subscription')),
  ADD COLUMN IF NOT EXISTS poll_url TEXT,
  ADD COLUMN IF NOT EXISTS meta JSONB DEFAULT '{}'::jsonb;

-- Activation & subscription payments have no booking
ALTER TABLE payments ALTER COLUMN booking_id DROP NOT NULL;

-- Webhook/poller look payments up by gateway reference
CREATE UNIQUE INDEX IF NOT EXISTS idx_payments_transaction_ref
  ON payments (transaction_ref);
