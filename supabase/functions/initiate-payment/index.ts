// Stage 20: Creates a Paynow transaction and a pending payments row.
//
// POST body: {
//   purpose: 'booking' | 'activation' | 'subscription',
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
const SUBSCRIPTION_PRICES: Record<string, number> = {
  activation: 3,
  monthly: 5,
};
const CLIENT_ACTIVATION_FEE = 1.0;

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

  if (purpose === "booking") {
    bookingId = String(body.bookingId ?? "");
    const { data: booking } = await admin
      .from("bookings")
      .select("id, client_id, provider_id, total_price, services(price)")
      .eq("id", bookingId)
      .maybeSingle();
    if (!booking || booking.client_id !== user.id) {
      return jsonResponse({ error: "Booking not found" }, 404);
    }
    amount = Number(booking.total_price ?? booking.services?.price ?? 0);
    providerId = booking.provider_id;
  } else if (purpose === "activation") {
    amount = CLIENT_ACTIVATION_FEE;
  } else if (purpose === "subscription") {
    const plan = String(body.tier ?? body.plan ?? "activation");
    const price = SUBSCRIPTION_PRICES[plan];
    if (!price) return jsonResponse({ error: "Invalid plan" }, 400);
    amount = price;
    providerId = user.id;
    meta.plan = plan;
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
