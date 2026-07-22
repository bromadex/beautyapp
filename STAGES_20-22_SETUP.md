# BeauTap — Stages 20, 21 & 22 Setup Guide

The app code for all three stages is shipped and works **today**: payments
fall back to the simulated flow and push stays silent until you complete the
external setup below. Nothing breaks in the meantime.

---

## 1. SQL migrations (do these first — 5 minutes)

Run these in the **Supabase Dashboard → SQL Editor** (project `suxohsmcgjzzllmyesgt`), in order:

1. `stage21_migration.sql` — subscription tiers, first-booking-free, featured waitlist
2. `stage20_migration.sql` — payments table columns for Paynow
3. `stage22_migration.sql` — fcm_token, reminder_sent, pg_cron reminder job
   ⚠️ Before running, replace `YOUR_SERVICE_ROLE_KEY` and `YOUR_WEBHOOK_SECRET`
   in the file (Service role key: Dashboard → Settings → API. Webhook secret:
   any long random string — you'll reuse it in step 3).

The app is already null-safe around all of these — you can run them anytime.

---

## 2. Stage 20 — Paynow (when your merchant account is ready)

**Register:** https://www.paynow.co.zw → create merchant account → create an
integration (gives you an **Integration ID** + **Integration Key**). Sandbox
keys work immediately; production keys arrive after approval (2-4 weeks).

**Deploy the edge functions** (Dashboard → Edge Functions → Deploy, or CLI):

```bash
supabase functions deploy initiate-payment
supabase functions deploy check-payment-status
supabase functions deploy paynow-webhook --no-verify-jwt   # Paynow can't send a JWT
```

**Set secrets** (Dashboard → Edge Functions → Secrets):

| Secret | Value |
|--------|-------|
| `PAYNOW_INTEGRATION_ID` | from Paynow |
| `PAYNOW_INTEGRATION_KEY` | from Paynow |
| `APP_RETURN_URL` | `https://beautyapp-swart.vercel.app` (optional, this is the default) |

That's it — the moment the secrets exist, the app automatically switches from
simulated to real payments (bookings, $1 activation, subscriptions). Remove
the secrets to fall back to simulation.

**In the Paynow merchant portal**, set the result URL to:
`https://suxohsmcgjzzllmyesgt.supabase.co/functions/v1/paynow-webhook`

**Test the WiFi edge case:** pay via EcoCash on a phone connected to WiFi with
the SIM removed — the app shows the "SIM must be in this phone" fallback
message on the waiting dialog.

---

## 3. Stage 22 — Push notifications (needs a Firebase project)

**Create the Firebase project:** https://console.firebase.google.com
1. Add project "BeauTap" (Analytics optional)
2. Add **Android app**, package name `com.beautap.app`
3. Add **Web app**
4. Project Settings → Cloud Messaging → **Web Push certificates** → generate → copy the VAPID key
5. Project Settings → Service accounts → **Generate new private key** → downloads a JSON file

**Fill in the app config** (then tell Claude to rebuild):
- `lib/config/firebase_config.dart` — paste Android + Web SDK values, VAPID key, set `firebaseConfigured = true`
- `web/firebase-messaging-sw.js` — paste the same web values, set `FIREBASE_CONFIGURED = true`

**Deploy the edge functions:**

```bash
supabase functions deploy push-dispatch --no-verify-jwt
supabase functions deploy send-reminders --no-verify-jwt
```

**Set secrets:**

| Secret | Value |
|--------|-------|
| `FCM_SERVICE_ACCOUNT` | the entire contents of the service account JSON file |
| `WEBHOOK_SECRET` | same random string you used in `stage22_migration.sql` |

**Create Database Webhooks** (Dashboard → Database → Webhooks):

| Name | Table | Events | Target |
|------|-------|--------|--------|
| `push-bookings` | `bookings` | INSERT, UPDATE | Edge function `push-dispatch` |
| `push-messages` | `messages` | INSERT | Edge function `push-dispatch` |

On both webhooks add HTTP header: `x-webhook-secret: <your WEBHOOK_SECRET>`.

**The 4 triggers, once live:**
1. New booking request → provider
2. Booking confirmed → client
3. New chat message → recipient
4. 1-hour reminder → both (pg_cron, every 15 min, no duplicates)

---

## What needs no action

- **Stage 21** works fully after its SQL migration: New tier (first booking
  free), Active $10/mo, Featured $25/mo with 3-slots-per-area + waitlist,
  featured-first search with FEATURED badge, service-radius slider in the
  profile editor, accept-gate with subscribe prompt.
- Payments keep working in simulated mode until Paynow secrets exist.
- Push code is dormant until `firebaseConfigured = true`.
