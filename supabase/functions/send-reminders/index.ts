// Lekka reminders: daily push notifications and manual pings.
//
// Two ways in:
//
// 1. Daily run, started by pg_cron at 09:00 India time (supabase/cron.sql) with
//    the x-cron-secret header. queue_reminders() decides who gets what
//    (2 days before, on the due date, every day while overdue), saves each
//    reminder for the Reminders screen, and returns the new ones to push.
//
// 2. Ping, called from the app by a signed-in lender with {"ping_loan_id": "..."}.
//    send_ping() runs as that person, so the database enforces the rules
//    (lender of a shared loan only, at most 3 per loan per day).
//
// Secrets (supabase secrets set ...):
//   CRON_SECRET               same value as for accrue-interest
//   FIREBASE_SERVICE_ACCOUNT  the Firebase service-account JSON, on one line.
//                             Without it reminders are still saved and shown
//                             in the app, but no push is sent.
// SUPABASE_URL, SUPABASE_ANON_KEY and SUPABASE_SERVICE_ROLE_KEY are provided
// by Supabase. The service-role key is used only here, on the server.
//
// Logs hold counts and error codes only: no names, amounts or tokens.

import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";
import { JWT } from "npm:google-auth-library@9";
import { buildMessage, type Reminder } from "./messages.ts";

const url = Deno.env.get("SUPABASE_URL")!;
const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, "Content-Type": "application/json" } });

interface Row extends Reminder {
  user_id: string;
  loan_id: string;
}

/** A short-lived Google access token for Firebase Cloud Messaging, or null when not set up. */
async function fcmAuth(): Promise<{ projectId: string; token: string } | null> {
  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) return null;
  const account = JSON.parse(raw);
  const jwt = new JWT({
    email: account.client_email,
    key: account.private_key,
    scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
  });
  const { token } = await jwt.getAccessToken();
  return token ? { projectId: account.project_id, token } : null;
}

/** Sends each reminder to every phone its receiver is signed in on. Returns how many pushes went out. */
async function push(admin: SupabaseClient, rows: Row[]): Promise<number> {
  if (rows.length === 0) return 0;
  const auth = await fcmAuth();
  if (!auth) return 0;

  const { data: tokens } = await admin
    .from("device_tokens")
    .select("token, user_id")
    .in("user_id", [...new Set(rows.map((r) => r.user_id))]);

  let sent = 0;
  for (const row of rows) {
    const text = buildMessage(row);
    for (const device of (tokens ?? []).filter((t) => t.user_id === row.user_id)) {
      const res = await fetch(`https://fcm.googleapis.com/v1/projects/${auth.projectId}/messages:send`, {
        method: "POST",
        headers: { Authorization: `Bearer ${auth.token}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token: device.token,
            notification: { title: text.title, body: text.body },
            data: { kind: row.kind, loan_id: row.loan_id },
            android: { priority: "high" },
            apns: { payload: { aps: { sound: "default" } } },
          },
        }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 400) {
        // The app was removed or the token is no longer valid: forget it.
        const body = await res.text();
        if (res.status === 404 || body.includes("UNREGISTERED") || body.includes("INVALID_ARGUMENT")) {
          await admin.from("device_tokens").delete().eq("token", device.token);
        }
        console.error("push failed:", res.status);
      } else {
        console.error("push failed:", res.status);
      }
    }
  }
  return sent;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
    auth: { persistSession: false },
  });

  // ---- 1. Daily run ------------------------------------------------------
  const secret = Deno.env.get("CRON_SECRET");
  if (secret && req.headers.get("x-cron-secret") === secret) {
    const { data, error } = await admin.rpc("queue_reminders");
    if (error) {
      console.error("queue_reminders failed:", error.message);
      return json({ ok: false, error: error.message }, 500);
    }
    const rows = (data ?? []) as Row[];
    const pushed = await push(admin, rows);
    console.log("reminders:", JSON.stringify({ saved: rows.length, pushed }));
    return json({ ok: true, saved: rows.length, pushed });
  }

  // ---- 2. Ping from the app ----------------------------------------------
  const authorization = req.headers.get("Authorization");
  let body: { ping_loan_id?: unknown } = {};
  try {
    body = await req.json();
  } catch {
    // handled below
  }
  if (!authorization || typeof body.ping_loan_id !== "string") {
    return json({ ok: false, error: "FORBIDDEN" }, 403);
  }

  // Runs as the caller: Row Level Security and send_ping's own checks apply.
  const asCaller = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: id, error } = await asCaller.rpc("send_ping", { p_loan_id: body.ping_loan_id });
  if (error) {
    if (error.message.includes("PING_LIMIT")) return json({ ok: false, error: "PING_LIMIT" }, 429);
    if (error.message.includes("PING_NOT_ALLOWED")) return json({ ok: false, error: "PING_NOT_ALLOWED" }, 403);
    console.error("send_ping failed:", error.code);
    return json({ ok: false, error: "FAILED" }, 400);
  }

  const { data: saved } = await admin
    .from("notifications")
    .select("user_id, loan_id, kind, to_lender, person_name, balance_paise, late_paise, due_date")
    .eq("id", id)
    .single();
  let pushed = 0;
  if (saved) {
    const { data: profile } = await admin.from("profiles").select("language").eq("id", saved.user_id).single();
    pushed = await push(admin, [{ ...saved, language: profile?.language ?? "en" } as Row]);
  }
  return json({ ok: true, pushed });
});
