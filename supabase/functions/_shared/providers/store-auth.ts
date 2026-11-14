// Signs the JWTs the App Store Server API and Google's OAuth token endpoint
// expect, with Web Crypto only (no extra dependencies in the Edge runtime).

function base64Url(bytes: Uint8Array): string {
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function encodeJson(value: unknown): string {
  return base64Url(new TextEncoder().encode(JSON.stringify(value)));
}

function pemToDer(pem: string): Uint8Array {
  const body = pem
    .replace(/\\n/g, "\n")
    .replace(/-----(BEGIN|END) [A-Z ]+-----/g, "")
    .replace(/\s+/g, "");
  return Uint8Array.from(atob(body), (c) => c.charCodeAt(0));
}

export async function signJwt(
  header: Record<string, unknown>,
  payload: Record<string, unknown>,
  privateKeyPem: string,
  algorithm: "ES256" | "RS256",
): Promise<string> {
  const keyAlgorithm = algorithm === "ES256"
    ? { name: "ECDSA", namedCurve: "P-256" }
    : { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" };
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(privateKeyPem),
    keyAlgorithm,
    false,
    ["sign"],
  );
  const signingInput = `${encodeJson({ ...header, alg: algorithm, typ: "JWT" })}.${encodeJson(payload)}`;
  const signAlgorithm = algorithm === "ES256" ? { name: "ECDSA", hash: "SHA-256" } : { name: "RSASSA-PKCS1-v1_5" };
  // Web Crypto's ECDSA output is already the raw r||s form JWS uses.
  const signature = await crypto.subtle.sign(signAlgorithm, key, new TextEncoder().encode(signingInput));
  return `${signingInput}.${base64Url(new Uint8Array(signature))}`;
}

// Reads a JWS payload without checking its signature. Only used on data
// fetched straight from Apple's API over TLS, never on client input.
export function decodeJwsPayload(jws: string): Record<string, unknown> {
  const part = jws.split(".")[1] ?? "";
  const base64 = part.replace(/-/g, "+").replace(/_/g, "/");
  const padded = base64 + "=".repeat((4 - (base64.length % 4)) % 4);
  const bytes = Uint8Array.from(atob(padded), (c) => c.charCodeAt(0));
  return JSON.parse(new TextDecoder().decode(bytes));
}
