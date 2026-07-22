// Stage 22: Receives Supabase Database Webhooks and sends the 3 event-driven
// critical pushes:
//   1. bookings INSERT              → provider ("New booking request")
//   2. bookings UPDATE → confirmed  → client   ("Booking confirmed")
//   3. messages INSERT              → receiver ("New message")
//
// Configure Database Webhooks (Dashboard → Database → Webhooks) on:
//   - bookings: INSERT + UPDATE → this function
//   - messages: INSERT → this function
// Add header: x-webhook-secret: <same value as the WEBHOOK_SECRET secret>
//
// Deploy with --no-verify-jwt. Secrets: FCM_SERVICE_ACCOUNT, WEBHOOK_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2";
import { getServiceAccount, pushToUser } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (secret && req.headers.get("x-webhook-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const sa = getServiceAccount();
  if (!sa) return new Response("FCM not configured", { status: 503 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // deno-lint-ignore no-explicit-any
  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad payload", { status: 400 });
  }

  const { type, table, record, old_record: oldRecord } = payload;

  try {
    if (table === "bookings" && type === "INSERT") {
      await pushToUser(admin, sa, {
        userId: record.provider_id,
        title: "New Booking Request 💅",
        body: "You have a new booking request. Open BeauTap to respond.",
        data: { route: "/provider/bookings", bookingId: String(record.id) },
      });
    } else if (
      table === "bookings" && type === "UPDATE" &&
      record.status === "confirmed" && oldRecord?.status !== "confirmed"
    ) {
      await pushToUser(admin, sa, {
        userId: record.client_id,
        title: "Booking Confirmed ✨",
        body: "Your stylist confirmed your booking. See the details in BeauTap.",
        data: { route: `/booking/${record.id}`, bookingId: String(record.id) },
      });
    } else if (table === "messages" && type === "INSERT") {
      const preview = (record.message ?? "").toString();
      await pushToUser(admin, sa, {
        userId: record.receiver_id,
        title: "New Message 💬",
        body: preview
          ? (preview.length > 80 ? `${preview.slice(0, 80)}…` : preview)
          : "You received a photo",
        data: {
          route: `/chat/${record.booking_id}`,
          bookingId: String(record.booking_id),
        },
      });
    }
  } catch (e) {
    console.error(`push-dispatch error: ${e}`);
    // Return 200 anyway — webhook retries won't fix an FCM misconfig
  }

  return new Response("OK", { status: 200 });
});
