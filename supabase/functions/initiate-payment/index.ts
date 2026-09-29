// Stage 20: Creates a Paynow transaction and a pending payments row.
//
// POST body: {
//   purpose: 'booking' | 'deposit' | 'featured' | 'activation' | 'subscription',
//   bookingId?: string,          // required for purpose=booking
//   method?: 'web' | 'ecocash' | 'onemoney' | 'telecash',
//   phone?: string,              // required for mobile money methods
//   tier?: 'activation' | 'monthly' // for purpose=subscription
// }
//
// Secrets required: PAYNOW_INTEGRATION_ID, PAYNOW_INTEGRATION_KEY
// Optional: APP_RETURN_URL (defaults to the BeauTap web app)

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  corsHeaders,
  getConfig,
  initiateTransaction,
  jsonResponse,
} from "../_shared/paynow.ts";

// Provider subscription: $3 activation (includes first month), $5/month after.
// No commission — providers keep 100% of booking payments.
// Salon: one plan covers the owner and up to 7 staff.
// Keep in step with public._fee_price() in the database.
const SUBSCRIPTION_PRICES: Record<string, number> = {
  activation: 3,
  monthly: 5,
  salon: 15,
};
// Product ads: 20 more listings for 30 days.
const PRODUCT_PACK_PRICE = 5;
const CLIENT_ACTIVATION_FEE = 1.0;
// Featured placement: top of Browse/Home in the stylist's city for 7 days.
const FEATURED_WEEK_PRICE = 3;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  const config = getConfig();
  if (!config) {
    // Signals the app to fall back to simulated payment
    return jsonResponse({ configured: false, error: "PAYNOW_NOT_CONFIGURED" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Authenticate the calling user
  const authHeader = req.headers.get("Authorization") ?? "";
  const { data: userData, error: userErr } = await admin.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (userErr || !userData.user) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }
  const user = userData.user;

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const purpose = String(body.purpose ?? "booking");
  const method = String(body.method ?? "web");
  const phone = body.phone ? String(body.phone) : undefined;
  const isExpress = method !== "web";
  if (isExpress && !phone) {
    return jsonResponse({ error: "Phone number required for mobile money" }, 400);
  }

  // ── Determine amount + payment row fields server-side (never trust client)
  let amount: number;
  let bookingId: string | null = null;
  let providerId: string | null = null;
  const meta: Record<string, unknown> = {};

  // Clients pay pros directly now; BeauTap only collects its own fees.
  if (purpose === "booking" || purpose === "deposit") {
    return jsonResponse({ error: "Pay your pro directly from the booking page" }, 400);
  }

  if (purpose === "booking" || purpose === "deposit") {
    bookingId = String(body.bookingId ?? "");
    const { data: booking } = await admin
      .from("bookings")
      .select("id, client_id, provider_id, total_price, deposit_amount, deposit_paid, payment_status, status")
      .eq("id", bookingId)
      .maybeSingle();
    if (!booking || booking.client_id !== user.id) {
      return jsonResponse({ error: "Booking not found" }, 404);
    }
    if (booking.status === "cancelled" || booking.payment_status === "paid") {
      return jsonResponse({ error: "This booking has nothing left to pay" }, 400);
    }
    const total = Number(booking.total_price ?? 0);
    const deposit = Number(booking.deposit_amount ?? 0);
    if (purpose === "deposit") {
      if (deposit <= 0 || booking.deposit_paid) {
        return jsonResponse({ error: "No deposit is due" }, 400);
      }
      amount = deposit;
    } else {
      amount = booking.deposit_paid ? Math.max(total - deposit, 0) : total;
    }
    providerId = booking.provider_id;
  } else if (purpose === "featured") {
    const { data: prof } = await admin
      .from("profiles").select("user_type").eq("id", user.id).maybeSingle();
    if (prof?.user_type !== "provider") {
      return jsonResponse({ error: "Only beauty pros can buy featured placement" }, 403);
    }
    amount = FEATURED_WEEK_PRICE;
    providerId = user.id;
    meta.days = 7;
  } else if (purpose === "activation") {
    amount = CLIENT_ACTIVATION_FEE;
  } else if (purpose === "subscription") {
    const plan = String(body.tier ?? body.plan ?? "activation");
    const price = SUBSCRIPTION_PRICES[plan];
    if (!price) return jsonResponse({ error: "Invalid plan" }, 400);
    if (plan !== "salon") {
      const { data: sub } = await admin
        .from("subscriptions").select("plan, status, end_date")
        .eq("provider_id", user.id).maybeSingle();
      if (
        sub?.plan === "salon" && sub.status === "active" &&
        sub.end_date >= new Date().toISOString().slice(0, 10)
      ) {
        return jsonResponse({ error: "Your salon plan already covers you" }, 400);
      }
    }
    if (plan === "salon") {
      const { data: salon } = await admin
        .from("salons").select("id").eq("owner_id", user.id).maybeSingle();
      if (!salon) return jsonResponse({ error: "Create your salon first" }, 400);
    }
    amount = price;
    providerId = user.id;
    meta.plan = plan;
  } else if (purpose === "product_pack") {
    const { data: prof } = await admin
      .from("profiles").select("user_type").eq("id", user.id).maybeSingle();
    if (prof?.user_type !== "provider") {
      return jsonResponse({ error: "Only beauty pros can advertise products" }, 403);
    }
    amount = PRODUCT_PACK_PRICE;
    providerId = user.id;
  } else {
    return jsonResponse({ error: "Invalid purpose" }, 400);
  }

  if (!amount || amount <= 0) {
    return jsonResponse({ error: "Invalid amount" }, 400);
  }

  const reference = `BT-${purpose.toUpperCase()}-${Date.now()}-${
    crypto.randomUUID().slice(0, 8)
  }`;

  const projectUrl = Deno.env.get("SUPABASE_URL")!;
  const resultUrl = `${projectUrl}/functions/v1/paynow-webhook`;
  const returnUrl = Deno.env.get("APP_RETURN_URL") ??
    "https://beautyapp-swart.vercel.app";

  const result = await initiateTransaction({
    config,
    reference,
    amount,
    email: user.email ?? "client@beautap.app",
    resultUrl,
    returnUrl,
    additionalInfo: `BeauTap ${purpose}`,
    phone,
    method: isExpress ? method : undefined,
  });

  if (!result.ok) {
    return jsonResponse({ configured: true, error: result.error }, 502);
  }

  // Pending payments row — the webhook / poller completes it
  const { data: payment, error: insertErr } = await admin
    .from("payments")
    .insert({
      booking_id: bookingId,
      client_id: user.id,
      provider_id: providerId,
      amount,
      method: isExpress ? "mobile_money" : "card",
      status: "pending",
      transaction_ref: reference,
      gateway: "paynow",
      currency: "USD",
      purpose,
      poll_url: result.pollUrl,
      meta,
    })
    .select("id")
    .single();

  if (insertErr) {
    return jsonResponse({ configured: true, error: insertErr.message }, 500);
  }

  return jsonResponse({
    configured: true,
    paymentId: payment.id,
    reference,
    browserUrl: result.browserUrl,
    instructions: result.instructions ??
      (isExpress
        ? "Check your phone and enter your mobile money PIN to approve the payment."
        : null),
  });
});
