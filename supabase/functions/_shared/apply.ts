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
  } else if (purpose === "subscription") {
    // $3 activation (includes first month) or $5 monthly renewal.
    const plan = payment.meta?.plan ?? "activation";
    const start = new Date();
    const dateOnly = (d: Date) => d.toISOString().split("T")[0];

    const { data: existing } = await admin
      .from("subscriptions")
      .select("id, end_date, status")
      .eq("provider_id", payment.client_id)
      .maybeSingle();

    // Renewals extend from the current end date; activations start today
    let base = start;
    if (plan === "monthly" && existing?.end_date) {
      const currentEnd = new Date(existing.end_date);
      if (currentEnd > start) base = currentEnd;
    }
    const end = new Date(base);
    end.setMonth(end.getMonth() + 1);

    const payload = {
      provider_id: payment.client_id,
      start_date: dateOnly(start),
      end_date: dateOnly(end),
      status: "active",
      plan,
      amount_paid: payment.amount,
      payment_ref: payment.transaction_ref,
    };

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
  }
}
