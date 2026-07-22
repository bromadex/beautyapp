// Shared Paynow helpers for BeauTap edge functions (Stage 20).
// Docs: https://developers.paynow.co.zw

const PAYNOW_INITIATE_URL =
  "https://www.paynow.co.zw/interface/initiatetransaction";
const PAYNOW_REMOTE_URL =
  "https://www.paynow.co.zw/interface/remotetransaction";

export interface PaynowConfig {
  integrationId: string;
  integrationKey: string;
}

export function getConfig(): PaynowConfig | null {
  const integrationId = Deno.env.get("PAYNOW_INTEGRATION_ID");
  const integrationKey = Deno.env.get("PAYNOW_INTEGRATION_KEY");
  if (!integrationId || !integrationKey) return null;
  return { integrationId, integrationKey };
}

/** SHA-512 hash of concatenated values + integration key, uppercase hex. */
export async function paynowHash(
  values: Record<string, string>,
  integrationKey: string,
): Promise<string> {
  let concat = "";
  for (const [key, value] of Object.entries(values)) {
    if (key.toLowerCase() !== "hash") concat += value;
  }
  concat += integrationKey;
  const digest = await crypto.subtle.digest(
    "SHA-512",
    new TextEncoder().encode(concat),
  );
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

export function parseUrlEncoded(body: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const [k, v] of new URLSearchParams(body).entries()) out[k] = v;
  return out;
}

/** Verifies the hash on a Paynow message (webhook or poll response). */
export async function verifyHash(
  fields: Record<string, string>,
  integrationKey: string,
): Promise<boolean> {
  const received = fields["hash"] ?? fields["Hash"];
  if (!received) return false;
  const expected = await paynowHash(fields, integrationKey);
  return expected === received.toUpperCase();
}

export interface InitiateResult {
  ok: boolean;
  error?: string;
  browserUrl?: string;
  pollUrl?: string;
  instructions?: string;
}

/** Creates a Paynow transaction. Pass phone+method for Express (USSD push). */
export async function initiateTransaction(opts: {
  config: PaynowConfig;
  reference: string;
  amount: number;
  email: string;
  resultUrl: string;
  returnUrl: string;
  additionalInfo?: string;
  phone?: string;
  method?: string; // ecocash | onemoney | telecash
}): Promise<InitiateResult> {
  const isExpress = !!(opts.phone && opts.method);

  // Field order matters: hash is computed over values in posted order.
  const fields: Record<string, string> = {
    id: opts.config.integrationId,
    reference: opts.reference,
    amount: opts.amount.toFixed(2),
    additionalinfo: opts.additionalInfo ?? "",
    returnurl: opts.returnUrl,
    resulturl: opts.resultUrl,
    authemail: opts.email,
    ...(isExpress ? { phone: opts.phone!, method: opts.method! } : {}),
    status: "Message",
  };
  fields["hash"] = await paynowHash(fields, opts.config.integrationKey);

  const res = await fetch(isExpress ? PAYNOW_REMOTE_URL : PAYNOW_INITIATE_URL, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams(fields).toString(),
  });
  const parsed = parseUrlEncoded(await res.text());
  const status = (parsed["status"] ?? "").toLowerCase();

  if (status !== "ok") {
    return { ok: false, error: parsed["error"] ?? `Paynow status: ${status}` };
  }
  return {
    ok: true,
    browserUrl: parsed["browserurl"],
    pollUrl: parsed["pollurl"],
    instructions: parsed["instructions"],
  };
}

/** Polls a Paynow transaction. Returns the raw status string (e.g. Paid). */
export async function pollTransaction(
  pollUrl: string,
  integrationKey: string,
): Promise<{ status: string; verified: boolean; paynowReference?: string }> {
  const res = await fetch(pollUrl);
  const fields = parseUrlEncoded(await res.text());
  const verified = await verifyHash(fields, integrationKey);
  return {
    status: fields["status"] ?? "Unknown",
    verified,
    paynowReference: fields["paynowreference"],
  };
}

export function corsHeaders(): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
  };
}

export function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...corsHeaders() },
  });
}
