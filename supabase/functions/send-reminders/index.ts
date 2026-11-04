// Booking reminders. Called by pg_cron every 15 minutes.
// Pros: confirmed bookings starting in 45-75 minutes (reminder_sent).
// Clients: at the time they chose (30 min, 1 h or 1 day before, or never),
// tracked by client_reminder_sent.
//
// Deploy with --no-verify-jwt. Secrets: FCM_SERVICE_ACCOUNT, WEBHOOK_SECRET.

import { createClient } from "npm:@supabase/supabase-js@2";
import { getServiceAccount, pushToUser } from "../_shared/fcm.ts";

Deno.serve(async (req) => {
  const secret = Deno.env.get("WEBHOOK_SECRET");
  if (!secret || req.headers.get("x-webhook-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const sa = getServiceAccount();
  if (!sa) return new Response("FCM not configured", { status: 503 });

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const now = Date.now();
  const from = new Date(now + 45 * 60 * 1000).toISOString();
  const to = new Date(now + 75 * 60 * 1000).toISOString();
  const label = (iso: string) =>
    new Date(iso).toLocaleTimeString("en-ZW", {
      hour: "2-digit",
      minute: "2-digit",
      timeZone: "Africa/Harare",
    });
  // Many-to-one embed: an object at runtime, typed as an array without generated types
  // deno-lint-ignore no-explicit-any
  const serviceOf = (b: any) => {
    const svc = Array.isArray(b.services) ? b.services[0] : b.services;
    return svc?.service_name ?? "your appointment";
  };

  // ---- pros: 1 hour before ----
  const { data: proDue, error } = await admin
    .from("bookings")
    .select("id, provider_id, booking_time, services(service_name)")
    .eq("status", "confirmed")
    .eq("reminder_sent", false)
    .gte("booking_time", from)
    .lte("booking_time", to);

  if (error) {
    console.error(`send-reminders query failed: ${error.message}`);
    return new Response(error.message, { status: 500 });
  }

  let sent = 0;
  for (const b of proDue ?? []) {
    // Mark first so a crash can't double-send on the next run
    await admin.from("bookings").update({ reminder_sent: true }).eq("id", b.id);
    await pushToUser(admin, sa, {
      userId: b.provider_id,
      title: "Upcoming booking",
      body: `${serviceOf(b)} starts around ${label(b.booking_time)}. Time to get ready!`,
      data: { route: `/booking/${b.id}`, bookingId: String(b.id) },
    });
    sent++;
  }

  // ---- clients: at the time they chose ----
  const { data: clientDue, error: cErr } = await admin
    .from("bookings")
    .select("id, client_id, booking_time, client_reminder_minutes, services(service_name)")
    .eq("status", "confirmed")
    .eq("client_reminder_sent", false)
    .gt("client_reminder_minutes", 0)
    .not("client_id", "is", null)
    .gt("booking_time", new Date(now).toISOString())
    .lte("booking_time", new Date(now + 25 * 3600 * 1000).toISOString());

  if (cErr) {
    console.error(`send-reminders client query failed: ${cErr.message}`);
    return new Response(cErr.message, { status: 500 });
  }

  for (const b of clientDue ?? []) {
    const start = new Date(b.booking_time).getTime();
    const remindAt = start - b.client_reminder_minutes * 60 * 1000;
    // Runs every 15 minutes: send once the chosen moment is within the next run.
    if (remindAt > now + 15 * 60 * 1000) continue;
    await admin.from("bookings").update({ client_reminder_sent: true }).eq("id", b.id);
    const hours = Math.round((start - now) / 3600000);
    const ahead = hours >= 2
      ? `in about ${hours} hours, at ${label(b.booking_time)}`
      : `at ${label(b.booking_time)}`;
    await pushToUser(admin, sa, {
      userId: b.client_id,
      title: "Booking reminder",
      body: `${serviceOf(b)} starts ${ahead}.`,
      data: { route: `/booking/${b.id}`, bookingId: String(b.id) },
    });
    sent++;
  }

  return new Response(JSON.stringify({ reminded: sent }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
