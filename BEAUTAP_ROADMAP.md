# BeauTap — Development Roadmap

> Agreed plan based on brainstorm review — July 2026
> Tightened with Kimi review — July 2026
> Stack: Flutter + Supabase | Target: Zimbabwe (mobile-first)

---

## Locked Decisions

| Decision | Answer |
|----------|--------|
| App name | BeauTap |
| Home screen | Two separate files — `ClientHomeScreen` + `ProviderHomeScreen` |
| Admin nav | Option B — button from home screen, no dedicated shell |
| Launch categories | Hair only (add Makeup in month 2 after 50+ bookings) |
| Client activation fee | $1 one-time — "Unlock unlimited bookings" |
| Provider pricing | $3 activation (includes first month) → $5/month after — **UPDATED July 2026** |
| Platform commission | **NONE** — providers keep 100% of booking payments; revenue = subscriptions only |
| Provider gating | Browse & message free; receiving/accepting bookings requires activation |
| Cancel policy | Cancel anytime → profile hidden; reactivate for $3 |
| Payment gateway | Paynow Zimbabwe (EcoCash, OneMoney, Telecash, Cards) |
| Navigation | Bottom nav with ShellRoutes, separate client/provider shells |
| Escrow | Deferred — build only after Paynow is live + 50 paid bookings |
| Multi-category | Deferred — Hair only at launch, expand after product-market fit |
| Reporting & Flagging | Deferred — basic admin tools are enough for now |

---

## Phase 1: Ship Mobile (Weeks 1-3)

### Stage 16: Navigation Overhaul ✅ DONE

**Goal:** Fix routing crashes, add bottom nav, split home screen.

**Changes:**
- Split `home_screen.dart` into `client_home_screen.dart` and `provider_home_screen.dart`
- Build `ClientShell` with bottom nav: Home | Browse | Bookings | Favourites
- Build `ProviderShell` with bottom nav: Home | Bookings | Earnings | Profile
- Convert router to use `ShellRoute` for persistent bottom nav
- Add `/` redirect to `/home` (fixes `GoException: no routes for /`)
- Fix all `context.go()` vs `context.push()` misuse on sub-screens
- Admin access: icon button in provider home app bar → `/admin/dashboard`
- Role-based routing: after login, route to correct shell based on `user_type`

**Bottom Nav Structure:**

```
ClientShell (bottom nav)
├── /home              → ClientHomeScreen (discovery, categories, search)
├── /browse            → BrowseScreen
├── /client/bookings   → ClientBookingsScreen
│   └── /booking/:id   → pushes on top (no bottom nav)
│       ├── /chat/:bookingId
│       ├── /payment/:bookingId
│       ├── /tracking/:bookingId
│       └── /review/:bookingId
└── /favorites         → FavoritesScreen

ProviderShell (bottom nav)
├── /home              → ProviderHomeScreen (dashboard, metrics, next booking)
├── /provider/bookings → ProviderBookingsScreen
│   └── /booking/:id   → pushes on top
│       ├── /chat/:bookingId
│       └── /tracking/:bookingId
├── /earnings          → ProviderEarningsScreen
└── /provider/profile  → Profile hub
    ├── /provider/profile/edit
    ├── /provider/services
    ├── /provider/gallery
    ├── /provider/promotions
    └── /provider/subscription

No Shell (full screen):
├── /login
├── /register
├── /verify
├── /verify/pending
├── /notifications
├── /recommended
├── /admin/*
└── /provider/:id (public profile)
```

**Back Button Rules:**
- Sub-screens: `context.pop()` → returns to parent tab
- After payment/review/booking: `context.go()` to relevant bookings tab
- Login → home: `context.go('/home')` clears auth stack
- Logout: `context.go('/login')` — clears shell and entire nav stack, no back navigation to authenticated screens

**Root redirect (`/`):**
- `/` redirects based on auth + role: not logged in → `/login`, provider → `/home` (ProviderShell), client → `/home` (ClientShell)
- Fixes `GoException: no routes for /` crash

**Files to create:**
- `lib/screens/client_home_screen.dart`
- `lib/screens/provider_home_screen.dart`
- `lib/widgets/client_shell.dart`
- `lib/widgets/provider_shell.dart`

**Files to modify:**
- `lib/router.dart` — full rewrite with ShellRoutes
- `lib/screens/home_screen.dart` — split into two, then delete or keep as redirect

---

### Stage 17: App Rebrand — BeauTap ✅ DONE (17a package name + 17b visual rebrand)

**Goal:** New identity across the entire app.

**Important sequencing:** Do the rebrand AFTER the first debug APK works (Stage 18). If the APK build breaks, you'll know whether it's the rebrand or the mobile build itself. **Exception:** Change package name to `com.beautap.app` immediately in Stage 17a — this is irreversible once published to Play Store, so set it early.

**Stage 17a (before APK):**
- Change package name to `com.beautap.app` (Android `build.gradle` + manifest)

**Stage 17b (after APK proven working):**

**Color Palette:**
| Role | Color | Hex |
|------|-------|-----|
| Primary | Deep Rose | `#C2185B` |
| Secondary | Warm Gold | `#F9A825` |
| Background | Soft Cream | `#FFF8F0` |
| Surface | White | `#FFFFFF` |
| Text | Rich Black | `#1A1A1A` |
| Success | Mint | `#4CAF50` |
| Error | Coral Red | `#E53935` |

**Changes:**
- Update `lib/theme.dart` — new AppColors, gradients, AppTheme
- Update app name everywhere: `pubspec.yaml`, `index.html`, Android `strings.xml`
- Update all hardcoded "Beauty Home Services" strings to "BeauTap"
- Add tagline: "Beauty at your fingertips"
- Splash screen: Deep Rose background + white BeauTap text (using `flutter_native_splash`)
- App icon: placeholder until logo asset provided (using `flutter_launcher_icons`)

**Files to modify:**
- `lib/theme.dart` — full color/theme rewrite
- `pubspec.yaml` — app name + splash/icon packages
- `web/index.html` — title, theme color, manifest
- `android/app/build.gradle` — applicationId → `com.beautap.app`
- `android/app/src/main/AndroidManifest.xml` — app label
- `android/app/src/main/res/values/strings.xml` — app name
- Every screen referencing "Beauty Home Services" in text

**Packages to add:**
```yaml
flutter_launcher_icons: ^0.14.x
flutter_native_splash: ^2.x
```

---

### Stage 18: APK Build ✅ DONE (tested on device; rebuilds paused until requested)

**Goal:** Working debug APK on a real Android phone.

**Note:** Same Flutter codebase — this is a cross-platform project, not a separate mobile project. `flutter build apk` compiles from the same `lib/` source. Web-specific packages (e.g., `flutter_web_plugins`) are conditionally imported and don't break APK builds.

**Pre-build checklist:**
- Package name set to `com.beautap.app` (done in Stage 17a)
- App icon configured (placeholder OK)
- Splash screen configured
- Min SDK set to 21 (Android 5.0+)
- All required permissions in AndroidManifest.xml:
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_COARSE_LOCATION`
  - `CAMERA`
  - `READ_EXTERNAL_STORAGE`
  - `POST_NOTIFICATIONS`
  - `FOREGROUND_SERVICE` (required for GPS tracking — "I'm On My Way" feature)

**Build commands:**
```bash
flutter build apk --debug          # for testing
flutter build apk --release        # for beta distribution
flutter build apk --split-per-abi  # smaller APKs per architecture
```

**Testing plan:**
- Install on own phone
- Complete full booking flow end-to-end
- Test GPS/location on mobile (native GPS differs from browser geolocation — different accuracy and permission flows)
- Test camera for verification
- Test back button behavior on every screen
- Test app kill + reopen (session persistence)
- Test "I'm On My Way" button — browser geolocation vs native GPS may behave differently
- Give APK to 1-2 friends, watch them use it
- Fix all mobile-specific bugs found

---

## Phase 2: Real Money (Weeks 4-6)

### Stage 19: Client Activation Fee ($1) ✅ DONE

**Goal:** One-time $1 payment gate after verification approval.

**Flow:**
```
Register → Verify identity → Admin approves → $1 activation wall → Full access
```

**Gate logic:**
- Not verified → verification wall
- Verified + not activated → $1 payment wall
- Verified + activated → browse and book freely

**DB changes:**
```sql
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS is_activated BOOLEAN DEFAULT false;
UPDATE profiles SET is_activated = true; -- grandfather existing accounts
```

**Files to create:**
- `lib/screens/activation_screen.dart` — payment UI with clear "one-time" messaging

**Files to modify:**
- Router — add activation check redirect
- Booking screen — gate check before allowing booking

**Note:** Initially uses simulated payment. Replaced by Paynow in Stage 20.

---

### Stage 20: Real Payments — Paynow Zimbabwe 🟡 CODE DONE — awaiting merchant account + deploy (see STAGES_20-22_SETUP.md)

**Goal:** Replace simulated payments with real EcoCash/Card payments.

**Architecture:**
```
Flutter → Supabase Edge Function → Paynow API → USSD push / Card page
Paynow webhook → Edge Function → DB update → Realtime → Flutter
```

**Edge Functions to build:**
| Function | Purpose |
|----------|---------|
| `initiate-payment` | Creates Paynow transaction, returns redirect/mobile prompt |
| `paynow-webhook` | Receives result, verifies signature, updates DB |
| `check-payment-status` | Polls Paynow status (fallback if webhook delayed) |

**What Paynow covers:**
- Service booking payments (EcoCash / OneMoney / Telecash / Card)
- $1 client activation fee
- Provider subscriptions

**DB changes:**
```sql
ALTER TABLE payments
  ADD COLUMN IF NOT EXISTS gateway TEXT DEFAULT 'paynow',
  ADD COLUMN IF NOT EXISTS gateway_ref TEXT,
  ADD COLUMN IF NOT EXISTS webhook_verified BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'USD';
```

**Security rules:**
- Never call Paynow from Flutter directly
- API keys only in Edge Function secrets
- Webhooks verified server-side with idempotency keys
- Retry logic on Edge Functions

**External dependencies:**
- Paynow merchant account registration (paynow.co.zw)
- Sandbox Integration ID + Key (available immediately — start sandbox integration early in this stage, don't wait for production credentials)
- Production credentials (after merchant approval, 2-4 weeks)

**Edge case:** Paynow USSD push requires the client's phone to be on the same network as their mobile money account. If the client is on WiFi with no SIM data, the USSD push may fail. Test this scenario and show a clear fallback message.

**Files to modify:**
- `lib/screens/payment_screen.dart` — replace simulation with real Paynow flow
- `lib/screens/subscription_screen.dart` — Paynow payment only
- `lib/screens/activation_screen.dart` — Paynow payment

---

### Stage 21: Provider Pricing — $3 Start, $5/Month, Zero Commission ✅ DONE

> **REVISED July 2026.** The original "First Booking Free + $10/$25 tiers" model
> was replaced before launch with a simpler, locked model. Featured tier,
> per-area slots, and the waitlist were scrapped.

**Goal:** Simple, honest pricing that funds the platform through subscriptions
instead of commission, and keeps fake accounts out.

**Provider journey:**
```
1. Create profile → FREE
2. Clients can browse and message → FREE
3. Accept first booking → requires $3 activation payment
4. First month active → the $3 covers month 1
5. Month 2 onward → $5/month renewal
6. Cancel anytime → profile hidden from search; reactivate for $3
```

**Pricing:**
| Payment | Amount | What It Covers |
|---------|--------|----------------|
| Activation | $3 one-time | Account activation + entire first month |
| Renewal | $5/month | Unlimited bookings + gallery + promos |
| Commission | **$0 — none** | Providers keep 100% of every booking payment |

**Why $3 (security):** prevents fake accounts and bot spam ($3 per fake adds
up), verifies a real payment method is attached, gives providers skin in the
game without being prohibitive — more effective than SMS verification alone.

**Key messaging:** "You keep 100% of what you earn" · "$3 to start, then
$5/month" · "No hidden fees, no commission".

**Enforcement (both directions):**
- Clients cannot create a booking with a provider who has no active
  subscription ("This stylist isn't accepting bookings yet — you can still
  message them!")
- Providers without an active subscription get an "Activate — $3" prompt when
  trying to accept

**DB changes (implemented in `pricing_update_migration.sql`):**
- `payments`: dropped `platform_fee` and `provider_earnings` — no commission split
- Removed the first-booking-free trigger
- `subscriptions.plan` values: `activation` | `monthly`; status may be `cancelled`

**Files modified:** ✅ `subscription_screen.dart` (full rewrite),
`payment_screen.dart`, `provider_earnings_screen.dart`,
`provider_bookings_screen.dart` (accept gate), `booking_screen.dart` (create
gate), `app_config.dart`, admin dashboard/analytics (subscription revenue
instead of commission), Paynow edge functions.

---

## Phase 3: Public Launch (Weeks 7-8)

### Stage 22: Push Notifications — FCM (Basic) 🟡 CODE DONE — awaiting Firebase project + deploy (see STAGES_20-22_SETUP.md)

**Goal:** 4 critical notification triggers via Firebase Cloud Messaging.

**Priority triggers only:**
1. New booking request → Provider
2. Booking confirmed → Client
3. New chat message → Recipient
4. 1-hour booking reminder → Both

**All other triggers deferred** (payment received, review, subscription expiry, promo alerts).

**Architecture:**
```
DB event → Supabase Edge Function → FCM HTTP v1 API → Device
```

**1-hour reminder requires `pg_cron`:** Triggers 1-4 are event-driven (DB insert/update fires Edge Function), but the 1-hour reminder needs a scheduled job. Use Supabase `pg_cron` extension to run a query every 15 minutes that finds bookings starting in 45-75 minutes and sends reminders via Edge Function. Mark bookings as reminded to avoid duplicates.

**DB changes:**
```sql
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
ALTER TABLE bookings ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT false;
```

**Flutter packages:**
```yaml
firebase_core: ^2.x
firebase_messaging: ^14.x
```

**External dependencies:**
- Create Firebase project
- Add Android app → `google-services.json`
- Add Web app → config in `index.html`
- Generate VAPID key for web push
- FCM Server Key in Supabase Edge Function secrets

**Permission flow:** Custom dialog on first login (1-2s delay), max 3 prompts then stop asking.

---

### Stage 23: Play Store Submission ⬜ NEXT UP

**Goal:** BeauTap on Google Play Store.

**Pre-submission:**
- Release APK signed with production keystore
- All mobile bugs fixed from Phase 1 testing
- Privacy policy page
- App screenshots (5-8)
- Feature graphic (1024x500)
- Short + full description

**Signing:**
```bash
keytool -genkey -v -keystore beautap.keystore \
        -alias beautap -keyalg RSA -keysize 2048 -validity 10000
flutter build appbundle --release
```

**Distribution path:**
1. Internal testing track → team testing
2. Closed testing → 20 beta providers
3. Open testing → public beta
4. Production → full launch

**Cost:** $25 one-time Google Developer account fee.

---

## Phase 4: Scale (After Launch)

These are deferred until the app has real users and real bookings:

| Stage | What | When |
|-------|------|------|
| 24 | Multi-Category (add Makeup) | After 50+ Hair bookings |
| 25 | Reporting & Flagging | After 100+ users |
| 26 | Escrow Payments | After Paynow live + dispute cases |
| 27 | Variable Subscriptions (per category) | After 2+ categories live |
| 28 | Advanced FCM (all 15 triggers) | After basic FCM proven |
| 29 | iOS Build | After Android stable + revenue |
| 30 | Loyalty & Rewards | After repeat booking data |

---

## Files Summary

### New files to create:
- `lib/screens/client_home_screen.dart`
- `lib/screens/provider_home_screen.dart`
- `lib/widgets/client_shell.dart`
- `lib/widgets/provider_shell.dart`
- `lib/screens/activation_screen.dart`

### Major rewrites:
- `lib/router.dart` — ShellRoute architecture
- `lib/theme.dart` — BeauTap color palette + theme

### Files modified across stages:
- `lib/screens/payment_screen.dart`
- `lib/screens/subscription_screen.dart`
- `lib/screens/booking_screen.dart`
- `lib/screens/browse_screen.dart`
- `pubspec.yaml`
- `web/index.html`
- `android/app/build.gradle`
- `android/app/src/main/AndroidManifest.xml`

### Files to retire:
- `lib/screens/home_screen.dart` → replaced by client/provider split

---

## Current State (Stages 1-15 Complete)

All original stages are built and deployed on Vercel:
1. Auth & Profiles
2. Identity Verification
3. Provider Management (Services, Gallery)
4. Subscriptions
5. Booking System
6. Location & Navigation + 6B GPS Tracking
7. In-App Chat
8. Payments (simulated)
9. Reviews & Ratings
10. Favorites
11. Browse & Search
12. Promotions
13. In-App Notifications
14. Admin Dashboard
15. Smart Matching

**Live at:** beautyapp-swart.vercel.app (will become beautap domain)

---

## Status Snapshot — July 2026

| Stage | Status |
|-------|--------|
| 16 Navigation Overhaul | ✅ Done |
| 17 Rebrand (package + visuals) | ✅ Done |
| 18 APK Build | ✅ Done — tested on device; rebuilds paused until requested |
| 19 Client Activation ($1) | ✅ Done — SQL migration run |
| 20 Paynow | 🟡 Code done — needs merchant account, function deploy, secrets, `stage20_migration.sql` |
| 21 Provider Pricing ($3/$5, 0% commission) | ✅ Done — run `pricing_update_migration.sql` |
| 22 FCM Push | 🟡 Code done — needs Firebase project, config values, function deploy, `stage22_migration.sql` |
| 23 Play Store | ⬜ Next — keystore, listing assets, privacy policy |

**Pricing revision (July 2026):** the Stage 21 tier model ($10 Active / $25
Featured, first booking free) was replaced pre-launch by the locked flat
model: **$3 activation including first month → $5/month, zero commission,
providers keep 100% of booking payments**. `stage21_migration.sql` is
obsolete — do not run it; use `pricing_update_migration.sql` instead.

**External setup guide:** see `STAGES_20-22_SETUP.md` for the exact Paynow /
Firebase / webhook steps.
