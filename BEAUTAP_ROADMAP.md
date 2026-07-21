# BeauTap — Development Roadmap

> Agreed plan based on brainstorm review — July 2026
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
| Subscription model | First Booking Free → then $10/mo Active tier |
| Payment gateway | Paynow Zimbabwe (EcoCash, OneMoney, Telecash, Cards) |
| Navigation | Bottom nav with ShellRoutes, separate client/provider shells |
| Escrow | Deferred — build only after Paynow is live + 50 paid bookings |
| Multi-category | Deferred — Hair only at launch, expand after product-market fit |
| Reporting & Flagging | Deferred — basic admin tools are enough for now |

---

## Phase 1: Ship Mobile (Weeks 1-3)

### Stage 16: Navigation Overhaul

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

**Files to create:**
- `lib/screens/client_home_screen.dart`
- `lib/screens/provider_home_screen.dart`
- `lib/widgets/client_shell.dart`
- `lib/widgets/provider_shell.dart`

**Files to modify:**
- `lib/router.dart` — full rewrite with ShellRoutes
- `lib/screens/home_screen.dart` — split into two, then delete or keep as redirect

---

### Stage 17: App Rebrand — BeauTap

**Goal:** New identity across the entire app.

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
- Change package name to `com.beautap.app` (Android `build.gradle` + manifest)
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

### Stage 18: APK Build

**Goal:** Working debug APK on a real Android phone.

**Pre-build checklist:**
- Package name set to `com.beautap.app`
- App icon configured (placeholder OK)
- Splash screen configured
- Min SDK set to 21 (Android 5.0+)
- All required permissions in AndroidManifest.xml:
  - `ACCESS_FINE_LOCATION`
  - `ACCESS_COARSE_LOCATION`
  - `CAMERA`
  - `READ_EXTERNAL_STORAGE`
  - `POST_NOTIFICATIONS`

**Build commands:**
```bash
flutter build apk --debug          # for testing
flutter build apk --release        # for beta distribution
flutter build apk --split-per-abi  # smaller APKs per architecture
```

**Testing plan:**
- Install on own phone
- Complete full booking flow end-to-end
- Test GPS/location on mobile
- Test camera for verification
- Test back button behavior on every screen
- Test app kill + reopen (session persistence)
- Give APK to 1-2 friends, watch them use it
- Fix all mobile-specific bugs found

---

## Phase 2: Real Money (Weeks 4-6)

### Stage 19: Client Activation Fee ($1)

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

### Stage 20: Real Payments — Paynow Zimbabwe

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
- Sandbox Integration ID + Key (available immediately)
- Production credentials (after merchant approval, 2-4 weeks)

**Files to modify:**
- `lib/screens/payment_screen.dart` — replace simulation with real Paynow flow
- `lib/screens/subscription_screen.dart` — Paynow payment only
- `lib/screens/activation_screen.dart` — Paynow payment

---

### Stage 21: Subscription Revamp — First Booking Free

**Goal:** New subscription model tied to proven value.

**Provider journey:**
```
1. Create profile → FREE
2. Clients can browse and message → FREE
3. Accept first booking → FREE (no subscription needed)
4. First booking completes → prompt: "Subscribe to keep accepting bookings"
5. Subscribe to Active ($10/mo) → full access continues
```

**Tiers:**
| Tier | Price | What You Get |
|------|-------|-------------|
| **New** | Free | Profile visible, messaging, accept 1st booking |
| **Active** | $10/mo | Unlimited bookings + gallery + promos |
| **Featured** | $25/mo | Top 3 search placement + promo tools (limited slots) |

**Featured tier scarcity:** Max 3 Featured providers per area. If all slots taken, waitlist. This keeps "priority in search" genuinely valuable.

**DB changes:**
- Update `subscriptions` table to support new tier structure
- Add `first_booking_used` boolean to `provider_profiles`
- Subscription check: allow booking acceptance if `first_booking_used = false` OR `subscription.status = 'active'`

**Files to modify:**
- `lib/screens/subscription_screen.dart` — new tier UI
- Booking acceptance logic — first-booking-free gate
- Browse/search — Featured providers at top

---

## Phase 3: Public Launch (Weeks 7-8)

### Stage 22: Push Notifications — FCM (Basic)

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

**DB changes:**
```sql
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS fcm_token TEXT;
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

### Stage 23: Play Store Submission

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
