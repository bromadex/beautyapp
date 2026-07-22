// Stage 20: Polls Paynow for a payment's status (fallback when the
// webhook is delayed). POST body: { paymentId: string }
// Returns { status: 'paid' | 'failed' | 'pending' }.

import { createClient } from "npm:@supabase/supabase-js@2";
import {
  corsHeaders,
  getConfig,
  jsonResponse,
  pollTransaction,
} from "../_shared/paynow.ts";
import { applyPaymentOutcome, classifyStatus } from "../_shared/apply.ts";

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders() });
  }

  const config = getConfig();
  if (!config) {
    return jsonResponse({ configured: false, error: "PAYNOW_NOT_CONFIGURED" });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const authHeader = req.headers.get("Authorization") ?? "";
  const { data: userData, error: userErr } = await admin.auth.getUser(
    authHeader.replace("Bearer ", ""),
  );
  if (userErr || !userData.user) {
    return jsonResponse({ error: "Unauthorized" }, 401);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "Invalid JSON body" }, 400);
  }

  const paymentId = String(body.paymentId ?? "");
  const { data: payment } = await admin
    .from("payments")
    .select("*")
    .eq("id", paymentId)
    .eq("client_id", userData.user.id) // only the payer may poll
    .maybeSingle();

  if (!payment) return jsonResponse({ error: "Payment not found" }, 404);

  // Already final — return stored state without hitting Paynow
  if (payment.status === "paid" || payment.status === "failed") {
    return jsonResponse({ configured: true, status: payment.status });
  }
  if (!payment.poll_url) {
    return jsonResponse({ configured: true, status: "pending" });
  }

  const poll = await pollTransaction(payment.poll_url, config.integrationKey);
  if (!poll.verified) {
    // Don't fail the app on a bad poll response; just report pending
    return jsonResponse({ configured: true, status: "pending" });
  }

  const outcome = classifyStatus(poll.status);
  if (outcome !== "pending") {
    await applyPaymentOutcome({
      admin,
      payment,
      outcome,
      paynowReference: poll.paynowReference,
      viaWebhook: false,
    });
  }

  return jsonResponse({ configured: true, status: outcome });
});
