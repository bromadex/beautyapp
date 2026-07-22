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

  if (purpose === "booking" && payment.booking_id) {
    await admin
      .from("bookings")
      .update({ payment_status: "paid" })
      .eq("id", payment.booking_id);

    if (payment.provider_id) {
      await admin.from("notifications").insert({
        user_id: payment.provider_id,
        type: "payment",
        title: "Payment Received",
        body: `You received $${
          Number(payment.provider_earnings ?? 0).toFixed(2)
        } for a booking`,
        reference_id: payment.booking_id,
      });
    }
  } else if (purpose === "activation") {
    await admin
      .from("profiles")
      .update({ is_activated: true })
      .eq("id", payment.client_id);
  } else if (purpose === "subscription") {
    const tier = payment.meta?.tier ?? "active";
    const months = Number(payment.meta?.months ?? 1);
    const start = new Date();
    const end = new Date(start);
    end.setMonth(end.getMonth() + months);
    const dateOnly = (d: Date) => d.toISOString().split("T")[0];

    const payload = {
      provider_id: payment.client_id,
      start_date: dateOnly(start),
      end_date: dateOnly(end),
      status: "active",
      plan: `${months}_month`,
      tier,
      amount_paid: payment.amount,
      payment_ref: payment.transaction_ref,
    };

    const { data: existing } = await admin
      .from("subscriptions")
      .select("id")
      .eq("provider_id", payment.client_id)
      .maybeSingle();

    if (existing) {
      await admin
        .from("subscriptions")
        .update(payload)
        .eq("provider_id", payment.client_id);
    } else {
      await admin.from("subscriptions").insert(payload);
    }

    await admin
      .from("provider_profiles")
      .update({ is_hidden: false })
      .eq("provider_id", payment.client_id);

    if (tier === "featured") {
      await admin
        .from("featured_waitlist")
        .update({ status: "activated" })
        .eq("provider_id", payment.client_id);
    }
  }
}
