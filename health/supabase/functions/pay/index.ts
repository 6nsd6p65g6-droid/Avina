// أفينا — تفعيل الاشتراك تلقائياً بعد الدفع بالبطاقة (Supabase Edge Function باسم "pay")
// يستقبل إشعارات Stripe (checkout.session.completed). رابط الدفع يحمل رقم الطلب في client_reference_id.
// الأسرار: STRIPE_WEBHOOK_SECRET (whsec_...) في Edge Functions ← Secrets.
import { createClient } from "npm:@supabase/supabase-js@2.117.3";

const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || Deno.env.get("SB_SECRET_KEY") || "";
const db = createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_KEY, { auth: { persistSession: false } });
const SECRET = Deno.env.get("STRIPE_WEBHOOK_SECRET") || "";
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

const reply = (status: number, msg: string) => new Response(msg, { status, headers: { "Content-Type": "text/plain" } });

function hex(buf: ArrayBuffer) {
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
function safeEqual(a: string, b: string) {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

// التحقق من توقيع Stripe: HMAC-SHA256 على "timestamp.body"
export async function verifyStripe(raw: string, header: string, secret: string, now = Date.now()): Promise<boolean> {
  const parts = Object.fromEntries(header.split(",").map((kv) => kv.split("=", 2)).filter((x) => x.length === 2).map(([k, v]) => [k.trim(), v.trim()]));
  const sigs = header.split(",").map((kv) => kv.trim()).filter((kv) => kv.startsWith("v1=")).map((kv) => kv.slice(3));
  const t = Number(parts.t);
  if (!t || !sigs.length || Math.abs(now / 1000 - t) > 300) return false;
  const key = await crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign"]);
  const mac = hex(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${t}.${raw}`)));
  return sigs.some((s) => safeEqual(s, mac));
}

if (import.meta.main) Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return reply(405, "method");
  if (!SECRET) return reply(500, "STRIPE_WEBHOOK_SECRET is not set");
  const raw = await req.text();
  if (!(await verifyStripe(raw, req.headers.get("stripe-signature") ?? "", SECRET))) return reply(400, "bad signature");

  let ev: { type?: string; data?: { object?: Record<string, unknown> } };
  try { ev = JSON.parse(raw); } catch { return reply(400, "bad json"); }
  if (ev.type !== "checkout.session.completed" && ev.type !== "checkout.session.async_payment_succeeded") return reply(200, "ignored");

  const s = ev.data?.object ?? {};
  const ref = String(s.client_reference_id ?? "");
  if (!UUID.test(ref)) return reply(200, "no reference");
  if (s.payment_status !== "paid") return reply(200, "not paid yet");

  const { data: p } = await db.from("payments").select("id,status,amount_usd,method").eq("id", ref).maybeSingle();
  if (!p) return reply(200, "unknown order");
  if (p.status !== "pending") return reply(200, "already handled");

  // المبلغ المدفوع يجب ألا يقل عن قيمة الطلب
  const paidCents = Number(s.amount_total ?? 0), currency = String(s.currency ?? "").toLowerCase();
  if (currency === "usd" && paidCents + 1 < Math.round(Number(p.amount_usd) * 100)) {
    await db.from("payments").update({ admin_note: `دُفع ${paidCents / 100}$ فقط عبر Stripe (${s.id}). راجعه يدوياً.` }).eq("id", ref);
    return reply(200, "amount mismatch");
  }
  const { error } = await db.rpc("activate_payment", { p_id: ref, p_by: null, p_ref: `stripe:${s.id}` });
  if (error && !/not_pending/.test(error.message)) return reply(500, "activate failed");
  return reply(200, "ok");
});
