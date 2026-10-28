import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import webpush from "npm:web-push@3.6.7";

const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-cron-secret", "Access-Control-Allow-Methods": "POST, OPTIONS", "Content-Type": "application/json" };
const response = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: cors });
const dateAtSaoPaulo = (date: Date) => {
  const parts = new Intl.DateTimeFormat("en-CA", { timeZone: "America/Sao_Paulo", year: "numeric", month: "2-digit", day: "2-digit" }).formatToParts(date);
  const part = (type: string) => parts.find((item) => item.type === type)?.value || "";
  return `${part("year")}-${part("month")}-${part("day")}`;
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return response({ error: "Method not allowed" }, 405);
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const vapidPublicKey = Deno.env.get("VAPID_PUBLIC_KEY");
  const vapidPrivateKey = Deno.env.get("VAPID_PRIVATE_KEY");
  const vapidSubject = Deno.env.get("VAPID_SUBJECT") || "mailto:admin@radiusbz1.local";
  if (!supabaseUrl || !serviceRoleKey || !vapidPublicKey || !vapidPrivateKey) return response({ error: "Missing server configuration" }, 500);
  webpush.setVapidDetails(vapidSubject, vapidPublicKey, vapidPrivateKey);
  const db = createClient(supabaseUrl, serviceRoleKey, { auth: { persistSession: false } });
  const cronSecret = req.headers.get("x-cron-secret") || "";
  const { data: authorized, error: authorizationError } = await db.rpc("validate_push_cron_secret", { candidate: cronSecret });
  if (authorizationError || authorized !== true) return response({ error: "Unauthorized" }, 401);

  const today = dateAtSaoPaulo(new Date());
  const tomorrowDate = new Date(new Date(today + "T12:00:00-03:00").getTime() + 86400000);
  const tomorrow = dateAtSaoPaulo(tomorrowDate);
  const { data: cones, error: coneError } = await db.from("cones").select("id,tag,name,area,due_date").not("due_date", "is", null);
  if (coneError) return response({ error: "Could not load cone inventory" }, 500);
  const { data: subscriptions, error: subError } = await db.from("push_subscriptions").select("id,user_id,endpoint,p256dh,auth");
  if (subError) return response({ error: "Could not load subscriptions" }, 500);

  let sent = 0, skipped = 0, removed = 0;
  for (const cone of cones || []) {
    const due = String(cone.due_date);
    const kind = due === tomorrow ? "tomorrow" : due === today ? "today" : due < today ? "expired" : null;
    if (!kind) continue;
    for (const sub of subscriptions || []) {
      const { data: existing } = await db.from("push_notification_log").select("id").eq("subscription_id", sub.id).eq("cone_id", cone.id).eq("due_date", due).eq("notification_kind", kind).maybeSingle();
      if (existing) { skipped++; continue; }
      const body = kind === "tomorrow"
        ? `O cone ${cone.tag} — ${cone.name} vence amanhã. Programe a abertura do chamado.`
        : kind === "today"
        ? `O cone ${cone.tag} — ${cone.name} vence hoje. Programe a abertura do chamado.`
        : `O cone ${cone.tag} — ${cone.name} está vencido desde ${due}. Verifique a abertura do chamado.`;
      try {
        await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, JSON.stringify({
          title: "RADIUS BZ1 — Alerta de vencimento", body, tag: `cone-${cone.id}-${kind}`, url: "/"
        }));
        const { error: logError } = await db.from("push_notification_log").insert({ subscription_id: sub.id, cone_id: cone.id, due_date: due, notification_kind: kind });
        if (logError) console.error("Could not record notification log", logError.message);
        sent++;
      } catch (error) {
        const statusCode = (error as { statusCode?: number })?.statusCode;
        if (statusCode === 404 || statusCode === 410) {
          await db.from("push_subscriptions").delete().eq("id", sub.id);
          removed++;
        } else {
          console.error("Push delivery failed", error);
        }
      }
    }
  }
  return response({ ok: true, today, tomorrow, sent, skipped, removed });
});
