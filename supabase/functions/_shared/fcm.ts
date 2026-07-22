// Shared FCM HTTP v1 helpers (Stage 22).
// Requires secret FCM_SERVICE_ACCOUNT: the full JSON of a Firebase service
// account key (Project Settings → Service accounts → Generate new key).

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedToken: { token: string; expiresAt: number } | null = null;

export function getServiceAccount(): ServiceAccount | null {
  const raw = Deno.env.get("FCM_SERVICE_ACCOUNT");
  if (!raw) return null;
  try {
    return JSON.parse(raw) as ServiceAccount;
  } catch {
    return null;
  }
}

function base64url(data: Uint8Array | string): string {
  const bytes = typeof data === "string"
    ? new TextEncoder().encode(data)
    : data;
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function importPrivateKey(pem: string): Promise<CryptoKey> {
  const body = pem
    .replace("-----BEGIN PRIVATE KEY-----", "")
    .replace("-----END PRIVATE KEY-----", "")
    .replace(/\s/g, "");
  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
}

/** OAuth2 access token for FCM, cached until 5 min before expiry. */
export async function getAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt - 300 > now) {
    return cachedToken.token;
  }

  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(JSON.stringify({
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  }));
  const unsigned = `${header}.${claims}`;

  const key = await importPrivateKey(sa.private_key);
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64url(new Uint8Array(sig))}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const data = await res.json();
  if (!data.access_token) {
    throw new Error(`FCM auth failed: ${JSON.stringify(data)}`);
  }
  cachedToken = { token: data.access_token, expiresAt: now + 3600 };
  return data.access_token;
}

/** Sends one push. Returns false on failure (e.g. stale token). */
export async function sendPush(opts: {
  sa: ServiceAccount;
  fcmToken: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<boolean> {
  const accessToken = await getAccessToken(opts.sa);
  const res = await fetch(
    `https://fcm.googleapis.com/v1/projects/${opts.sa.project_id}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${accessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        message: {
          token: opts.fcmToken,
          notification: { title: opts.title, body: opts.body },
          data: opts.data ?? {},
        },
      }),
    },
  );
  if (!res.ok) {
    console.error(`FCM send failed (${res.status}): ${await res.text()}`);
    return false;
  }
  return true;
}

/** Looks up a user's fcm_token and pushes to it. No-op without a token. */
// deno-lint-ignore no-explicit-any
export async function pushToUser(admin: any, sa: ServiceAccount, opts: {
  userId: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}): Promise<void> {
  const { data: profile } = await admin
    .from("profiles")
    .select("fcm_token")
    .eq("id", opts.userId)
    .maybeSingle();
  const token = profile?.fcm_token;
  if (!token) return;
  const ok = await sendPush({
    sa,
    fcmToken: token,
    title: opts.title,
    body: opts.body,
    data: opts.data,
  });
  if (!ok) {
    // Clear stale tokens so we stop retrying dead devices
    await admin
      .from("profiles")
      .update({ fcm_token: null })
      .eq("id", opts.userId);
  }
}
