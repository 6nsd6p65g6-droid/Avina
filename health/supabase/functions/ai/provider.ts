// أفينا — مزوّد ذكاء اصطناعي متوافق مع واجهة OpenAI (مثل Groq المجاني، أو OpenRouter، أو Cerebras).
// يُضبط من Edge Functions ← Secrets:
//   GROQ_API_KEY أو AI_API_KEY  مفتاح المزوّد (سري)
//   AI_BASE_URL   (اختياري) عنوان الواجهة. الافتراضي Groq.
//   AI_MODEL      (اختياري) نموذج أو أكثر مفصولة بفواصل؛ يُجرَّب التالي إذا بلغ الأول حدّه أو لم يعد متاحاً.
//   AI_MODEL_BEST (اختياري) نموذج أقوى لخطة ألترا ولمقالات الموسوعة. الافتراضي AI_MODEL.

export type Turn = { role: "user" | "assistant"; content: string };
export type OpenConfig = { baseUrl: string; apiKey: string; models: string[]; bestModels: string[] };

const list = (s: string | undefined) => (s ?? "").split(",").map((x) => x.trim()).filter(Boolean);

export function openConfig(env: (k: string) => string | undefined): OpenConfig | null {
  const apiKey = env("AI_API_KEY") || env("GROQ_API_KEY") || "";
  if (!apiKey) return null;
  const models = list(env("AI_MODEL"));
  if (!models.length) models.push("openai/gpt-oss-120b", "llama-3.3-70b-versatile");
  const best = list(env("AI_MODEL_BEST"));
  return {
    baseUrl: (env("AI_BASE_URL") || "https://api.groq.com/openai/v1").replace(/\/+$/, ""),
    apiKey,
    models,
    bestModels: best.length ? best : models,
  };
}

export class ProviderError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
  /** المزوّد مزدحم أو بلغ الحد المجاني */
  get busy() {
    return this.status === 429 || this.status === 503;
  }
}

// يجرّب النماذج بالترتيب: ينتقل للتالي عند بلوغ الحد (429) أو غياب النموذج (404) أو رفض الطلب بسبب اسمه
async function post(cfg: OpenConfig, models: string[], body: Record<string, unknown>, signal?: AbortSignal): Promise<{ res: Response; model: string }> {
  let last = new ProviderError(502, "no model tried");
  for (const model of models) {
    const send = (b: Record<string, unknown>) =>
      fetch(`${cfg.baseUrl}/chat/completions`, {
        method: "POST",
        headers: { Authorization: `Bearer ${cfg.apiKey}`, "Content-Type": "application/json" },
        body: JSON.stringify({ ...b, model }),
        signal,
      });
    let res = await send(body);
    if (res.ok) return { res, model };
    let text = (await res.text()).slice(0, 400);
    // بعض النماذج تسمّي حدّ الطول max_completion_tokens
    if (res.status === 400 && /max_tokens/i.test(text) && "max_tokens" in body) {
      const { max_tokens, ...rest } = body;
      res = await send({ ...rest, max_completion_tokens: max_tokens });
      if (res.ok) return { res, model };
      text = (await res.text()).slice(0, 400);
    }
    last = new ProviderError(res.status, `${model}: ${res.status} ${text}`);
    const modelProblem = res.status === 404 || (res.status === 400 && /model/i.test(text) && !/response_format|json/i.test(text));
    if (res.status === 401 || res.status === 403) throw last; // المفتاح خاطئ: لا فائدة من نموذج آخر
    if (res.status === 429 || res.status === 503 || modelProblem) continue;
    throw last;
  }
  throw last;
}

// يحذف مقاطع التفكير <think>…</think> التي تضعها بعض النماذج المفتوحة داخل النص
export function thinkFilter() {
  let buf = "", inside = false;
  return {
    push(chunk: string): string {
      buf += chunk;
      let out = "";
      for (;;) {
        if (inside) {
          const end = buf.indexOf("</think>");
          if (end < 0) { buf = buf.slice(-8); return out; }
          buf = buf.slice(end + 8).replace(/^\s+/, "");
          inside = false;
        } else {
          const start = buf.indexOf("<think>");
          if (start >= 0) { out += buf.slice(0, start); buf = buf.slice(start + 7); inside = true; continue; }
          // أبقِ ذيلاً قد يكون بداية وسم لم يكتمل
          const keep = Math.max(0, buf.lastIndexOf("<"));
          const partial = buf.slice(keep);
          if (partial && "<think>".startsWith(partial)) { out += buf.slice(0, keep); buf = partial; }
          else { out += buf; buf = ""; }
          return out;
        }
      }
    },
    end(): string {
      const rest = inside ? "" : buf;
      buf = "";
      return rest;
    },
  };
}

/** محادثة متدفقة: تعيد مولّداً لمقاطع النص بعد أن يقبل المزوّد الطلب (فتظهر أخطاء الحد والمفتاح قبل بدء الرد). */
export async function openChat(cfg: OpenConfig, models: string[], system: string, turns: Turn[], maxTokens: number, signal?: AbortSignal) {
  const { res, model } = await post(cfg, models, {
    messages: [{ role: "system", content: system }, ...turns],
    stream: true,
    max_tokens: maxTokens,
  }, signal);
  if (!res.body) throw new ProviderError(502, "empty body");
  const reader = res.body.getReader();
  async function* chunks(): AsyncGenerator<string> {
    const dec = new TextDecoder(), filter = thinkFilter();
    let buf = "";
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      buf += dec.decode(value, { stream: true });
      let nl: number;
      while ((nl = buf.indexOf("\n")) >= 0) {
        const line = buf.slice(0, nl).trim();
        buf = buf.slice(nl + 1);
        if (!line.startsWith("data:")) continue;
        const data = line.slice(5).trim();
        if (data === "[DONE]") { const t = filter.end(); if (t) yield t; return; }
        try {
          const piece = JSON.parse(data)?.choices?.[0]?.delta?.content;
          if (typeof piece === "string" && piece) { const t = filter.push(piece); if (t) yield t; }
        } catch { /* سطر غير مكتمل أو تعليق: تجاهله */ }
      }
    }
    const t = filter.end();
    if (t) yield t;
  }
  return { model, chunks: chunks(), cancel: () => reader.cancel().catch(() => {}) };
}

function extractJSON(text: string): unknown {
  const t = thinkFilter();
  const clean = (t.push(text) + t.end()).replace(/^\s*```(?:json)?/i, "").replace(/```\s*$/, "").trim();
  const a = clean.indexOf("{"), b = clean.lastIndexOf("}");
  if (a < 0 || b <= a) throw new Error("no json object");
  return JSON.parse(clean.slice(a, b + 1));
}

// تحقق خفيف: الحقول المطلوبة موجودة وقيم enum صحيحة (التطبيق ينظّف الباقي)
function conforms(obj: unknown, schema: Record<string, unknown>): boolean {
  if (!obj || typeof obj !== "object" || Array.isArray(obj)) return false;
  const o = obj as Record<string, unknown>;
  const props = (schema.properties ?? {}) as Record<string, { type?: string; enum?: unknown[] }>;
  for (const k of (schema.required ?? []) as string[]) {
    if (!(k in o)) return false;
    const p = props[k];
    if (p?.enum && !p.enum.includes(o[k])) return false;
    if (p?.type === "array" && !Array.isArray(o[k])) return false;
    if (p?.type === "string" && typeof o[k] !== "string") return false;
  }
  return true;
}

/** رد JSON مطابق للمخطط. يجرّب json_schema ثم json_object ثم نصاً عادياً، حسب ما يدعمه المزوّد والنموذج. */
export async function openJSON(cfg: OpenConfig, models: string[], system: string, prompt: string, schema: Record<string, unknown>, name: string, maxTokens: number) {
  const messages = [
    { role: "system", content: system },
    { role: "user", content: `${prompt}\n\nأعد كائن JSON واحداً فقط يطابق هذا المخطط (JSON Schema) تماماً، بلا أي نص قبله أو بعده:\n${JSON.stringify(schema)}` },
  ];
  const formats: Array<Record<string, unknown>> = [
    { response_format: { type: "json_schema", json_schema: { name, strict: true, schema } } },
    { response_format: { type: "json_object" } },
    {},
  ];
  let last: unknown = new Error("no attempt");
  for (const fmt of formats) {
    try {
      const { res, model } = await post(cfg, models, { messages, max_tokens: maxTokens, ...fmt });
      const text = (await res.json())?.choices?.[0]?.message?.content;
      const obj = extractJSON(typeof text === "string" ? text : "");
      if (!conforms(obj, schema)) throw new Error("schema mismatch");
      return { value: obj as Record<string, unknown>, model };
    } catch (e) {
      last = e;
      // حدّ الاستخدام أو خطأ المفتاح لا يتغيّر بتغيير الصيغة
      if (e instanceof ProviderError && (e.busy || e.status === 401 || e.status === 403)) throw e;
    }
  }
  throw last;
}
