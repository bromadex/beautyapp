-- ============================================================
-- Stage 22: Push Notifications — FCM (Basic)
-- Run this in the Supabase Dashboard SQL editor (project suxohsmcgjzzllmyesgt)
-- Safe to run more than once.
--
-- BEFORE the pg_cron section below, replace YOUR_SERVICE_ROLE_KEY and
-- YOUR_WEBHOOK_SECRET with real values (Dashboard → Settings → API).
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT false;

-- ── 1-hour reminder job (runs every 15 minutes) ─────────────
-- Requires the pg_cron + pg_net extensions:
CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Remove a previous version of the job if it exists
SELECT cron.unschedule('beautap-booking-reminders')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'beautap-booking-reminders'
);

SELECT cron.schedule(
  'beautap-booking-reminders',
  '*/15 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://suxohsmcgjzzllmyesgt.supabase.co/functions/v1/send-reminders',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY',
      'x-webhook-secret', 'YOUR_WEBHOOK_SECRET'
    ),
    body := '{}'::jsonb
  );
  $$
);
