// Stage 22: 1-hour booking reminders (trigger 4). Called by pg_cron every
// 15 minutes (see stage22_migration.sql). Finds confirmed bookings starting
// in 45-75 minutes, pushes to both parties, marks reminder_sent.
//
// Deploy with --no-verify-jwt. Secrets: FCM_SERVICE_ACCOUNT, WEBHOOK_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2";
import { getServiceAccount, pushToUser } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
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

  const from = new Date(Date.now() + 45 * 60 * 1000).toISOString();
  const to = new Date(Date.now() + 75 * 60 * 1000).toISOString();

  const { data: bookings, error } = await admin
    .from("bookings")
    .select("id, client_id, provider_id, booking_time, services(service_name)")
    .eq("status", "confirmed")
    .eq("reminder_sent", false)
    .gte("booking_time", from)
    .lte("booking_time", to);

  if (error) {
    console.error(`send-reminders query failed: ${error.message}`);
    return new Response(error.message, { status: 500 });
  }

  let sent = 0;
  for (const b of bookings ?? []) {
    const service = b.services?.service_name ?? "your appointment";
    const when = new Date(b.booking_time).toLocaleTimeString("en-ZW", {
      hour: "2-digit",
      minute: "2-digit",
    });

    await pushToUser(admin, sa, {
      userId: b.client_id,
      title: "Upcoming Booking ⏰",
      body: `${service} starts around ${when}. Your stylist is getting ready!`,
      data: { route: `/booking/${b.id}`, bookingId: String(b.id) },
    });
    await pushToUser(admin, sa, {
      userId: b.provider_id,
      title: "Upcoming Booking ⏰",
      body: `${service} starts around ${when}. Time to head out soon!`,
      data: { route: `/booking/${b.id}`, bookingId: String(b.id) },
    });

    // Mark first so a crash can't double-send on the next run
    await admin
      .from("bookings")
      .update({ reminder_sent: true })
      .eq("id", b.id);
    sent++;
  }

  return new Response(JSON.stringify({ reminded: sent }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
