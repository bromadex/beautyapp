// Applies the business effects of a completed (or failed) Paynow payment.
// Used by both paynow-webhook and check-payment-status. Idempotent.

// deno-lint-ignore no-explicit-any
type SupabaseAdmin = any;
// deno-lint-ignore no-explicit-any
type PaymentRow = Record<string, any>;

const PAID_STATUSES = ["paid", "awaiting delivery", "delivered"];
const FAILED_STATUSES = ["cancelled", "failed", "disputed", "refunded"];

export function classifyStatus(
  paynowStatus: string,
): "paid" | "failed" | "pending" {
  const s = paynowStatus.toLowerCase();
  if (PAID_STATUSES.includes(s)) return "paid";
  if (FAILED_STATUSES.includes(s)) return "failed";
  return "pending";
}

export async function applyPaymentOutcome(opts: {
  admin: SupabaseAdmin;
  payment: PaymentRow;
  outcome: "paid" | "failed";
  paynowReference?: string;
  viaWebhook: boolean;
}): Promise<void> {
  const { admin, payment, outcome, paynowReference, viaWebhook } = opts;

  // Idempotency: never re-apply a final state
  if (payment.status === "paid" || payment.status === "failed") return;

  await admin
    .from("payments")
    .update({
      status: outcome,
      gateway_ref: paynowReference ?? payment.gateway_ref,
      webhook_verified: viaWebhook ? true : payment.webhook_verified,
      paid_at: outcome === "paid" ? new Date().toISOString() : null,
    })
    .eq("id", payment.id)
    .eq("status", "pending"); // guard against concurrent completion

  if (outcome !== "paid") return;

  const purpose = payment.purpose ?? "booking";

  if (purpose === "deposit" && payment.booking_id) {
    await admin
      .from("bookings")
      .update({ deposit_paid: true })
      .eq("id", payment.booking_id);
    if (payment.provider_id) {
      await admin.from("notifications").insert({
        user_id: payment.provider_id,
        type: "payment",
        title: "Deposit Received",
        body: `Your client paid a $${Number(payment.amount ?? 0).toFixed(2)} deposit. Please confirm the booking.`,
        reference_id: payment.booking_id,
      });
    }
  } else if (purpose === "booking" && payment.booking_id) {
    await admin
      .from("bookings")
      .update({ payment_status: "paid" })
      .eq("id", payment.booking_id);

    if (payment.provider_id) {
      // No commission — the provider receives the full amount
      await admin.from("notifications").insert({
        user_id: payment.provider_id,
        type: "payment",
        title: "Payment Received",
        body: `You received $${
          Number(payment.amount ?? 0).toFixed(2)
        } for a booking — 100% yours`,
        reference_id: payment.booking_id,
      });
    }
  } else if (purpose === "activation") {
    await admin
      .from("profiles")
      .update({ is_activated: true })
      .eq("id", payment.client_id);
  } else if (
    purpose === "subscription" || purpose === "featured" || purpose === "product_pack"
  ) {
    // Plans, featured weeks and product packs are applied in the database
    // (public._apply_fee) so Paynow and manual EcoCash payments behave the same.
    const { error } = await admin.rpc("_apply_fee", {
      p_user: payment.client_id,
      p_purpose: purpose,
      p_plan: payment.meta?.plan ?? null,
      p_amount: payment.amount,
      p_ref: payment.transaction_ref ?? payment.gateway_ref ?? null,
      p_record: false,
    });
    if (error) console.error(`apply fee failed: ${error.message}`);
  }
}
