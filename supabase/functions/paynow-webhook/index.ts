// Stage 20: Paynow result URL (webhook). Paynow POSTs urlencoded fields:
// reference, paynowreference, amount, status, pollurl, hash.
// Signature is verified before any DB write. Idempotent.
//
// Deploy with --no-verify-jwt (Paynow cannot send a Supabase JWT):
//   supabase functions deploy paynow-webhook --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2";
import { getConfig, parseUrlEncoded, verifyHash } from "../_shared/paynow.ts";
import { applyPaymentOutcome, classifyStatus } from "../_shared/apply.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const config = getConfig();
  if (!config) return new Response("Not configured", { status: 503 });

  const fields = parseUrlEncoded(await req.text());
  const reference = fields["reference"];
  if (!reference) return new Response("Missing reference", { status: 400 });

  // Verify Paynow signature — reject anything unsigned/forged
  if (!(await verifyHash(fields, config.integrationKey))) {
    console.error(`paynow-webhook: bad hash for reference ${reference}`);
    return new Response("Invalid hash", { status: 403 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: payment } = await admin
    .from("payments")
    .select("*")
    .eq("transaction_ref", reference)
    .maybeSingle();

  if (!payment) {
    console.error(`paynow-webhook: unknown reference ${reference}`);
    return new Response("Unknown reference", { status: 404 });
  }

  const outcome = classifyStatus(fields["status"] ?? "");
  if (outcome !== "pending") {
    await applyPaymentOutcome({
      admin,
      payment,
      outcome,
      paynowReference: fields["paynowreference"],
      viaWebhook: true,
    });
  }

  return new Response("OK", { status: 200 });
});
