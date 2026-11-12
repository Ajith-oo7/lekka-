// Lekka daily interest job.
//
// Started by pg_cron at 00:30 India time (see supabase/cron.sql). It runs the
// accrue_interest() database function, which adds interest and late interest
// entries to Records for the day that just ended, and catches up any missed days.
// All the maths lives in that function (supabase/migrations/phase3_update.sql) so
// a whole run is one database transaction.
//
// Secrets (set with `supabase secrets set`):
//   CRON_SECRET                - shared with the cron job; callers without it get 403
//   SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY - provided by Supabase automatically
//
// The service-role key is used only here, on the server. Never in the app.

import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req) => {
  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return new Response("Forbidden", { status: 403 });
  }

  const client = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false } },
  );

  // Optional {"until": "YYYY-MM-DD"} for a manual run; otherwise yesterday in India.
  let until: string | null = null;
  try {
    const body = await req.json();
    if (typeof body?.until === "string" && /^\d{4}-\d{2}-\d{2}$/.test(body.until)) until = body.until;
  } catch {
    // No body: normal daily run.
  }

  const { data, error } = await client.rpc("accrue_interest", until ? { p_until: until } : {});
  if (error) {
    // Log the error only: no names or amounts.
    console.error("accrue_interest failed:", error.message);
    return Response.json({ ok: false, error: error.message }, { status: 500 });
  }
  console.log("accrue_interest done:", JSON.stringify(data)); // counts only
  return Response.json({ ok: true, ...data });
});
