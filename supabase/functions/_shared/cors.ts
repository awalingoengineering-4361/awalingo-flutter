// Supabase Edge Functions don't handle CORS automatically — the browser
// (Flutter web) sends an OPTIONS preflight before the real POST/GET, and
// every actual response also needs these headers or the browser blocks it
// even on a 200. Mobile/native callers ignore CORS entirely, so this is
// purely for the web target.
export const corsHeaders: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

export function handleCorsPreflight(req: Request): Response | null {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 200, headers: corsHeaders });
  }
  return null;
}
