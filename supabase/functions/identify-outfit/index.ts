import { createClient } from "npm:@supabase/supabase-js@2";

// identify-outfit: one selfie -> the garments visible in it, each with up to 3 ranked closet candidates.
// Runs as the signed-in user (their JWT). Writes NOTHING; the app logs the outfit after Joe reviews the list.
// Body: { image: { media_type: "image/jpeg"|"image/png"|"image/webp", data: "<base64>" } }
// Secrets: ANTHROPIC_API_KEY (required), ANTHROPIC_MODEL (optional, default below).
// v2 (2026-10-20): max_tokens 4096, short `why`, every failure path logs its cause, max_tokens cut-off has its own error.

const cors = {
  "Access-Control-Allow-Origin": "https://joegrimaldi.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });
const fail = (status: number, error: string, detail?: unknown) => {
  console.error(`identify-outfit ${status}: ${error}`, detail === undefined ? "" : detail);
  return json({ error }, status);
};

const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
const SLOTS = ["outer", "top", "layer", "bottom", "shoes", "belt", "accessory"];
const CONF = ["high", "medium", "low"];

function systemPrompt(closet: string, today: string) {
  return `You look at one photo of Joe (usually a mirror selfie) and list the garments and accessories that are VISIBLE in it, matching each to his closet database when possible. Today is ${today}.

HARD RULES
- Only what is visible. Never infer a watch from a wrist, headphones from a cable, a belt under an untucked shirt, socks under trousers, or a layer that isn't shown. Earbuds, phones, bags in hand and shopping bags are not garments. If you cannot see it, it is not in the list.
- One entry per visible garment. For each, give up to 3 ranked closet candidates, best first.
- Joe repeats pieces heavily. When two closet items look alike, prefer the one worn more recently (the closet list shows last worn and wears in the last 30 days) and say so in "why".
- If nothing in the closet fits a visible garment, return "candidates": []. Never force a match.
- "seen" is a short neutral description of what the photo shows (colour, type, visible details), independent of the closet. Keep it under 10 words.
- Keep each "why" under 15 words.
- Confidence: high = colour, type and visible details all match one closet item; medium = plausible but another item or an unlisted piece is possible; low = a guess from colour and type only.

CLOSET (one line per item):
#id | name | brand | colours | layer | category | material | last worn | wears in last 30 days
${closet}

Return ONLY one JSON object, no prose, no code fences:
{
  "garments": [
    { "slot": "outer"|"top"|"layer"|"bottom"|"shoes"|"belt"|"accessory",
      "seen": string,
      "candidates": [ { "item_id": number, "confidence": "high"|"medium"|"low", "why": string } ] }
  ]
}`;
}

function parseJson(text: string) {
  const t = text.replace(/```json|```/g, "").trim();
  const s = t.indexOf("{"), e = t.lastIndexOf("}");
  return JSON.parse(t.slice(s, e + 1));
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return fail(405, "POST only");

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return fail(503, "ANTHROPIC_API_KEY is not set in Supabase function secrets");

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: u, error: ue } = await sb.auth.getUser();
  if (!u?.user) return fail(401, "not signed in", ue?.message);

  let body: any;
  try { body = await req.json(); } catch (e) { return fail(400, "bad json", String(e)); }
  const im = body?.image;
  if (!["image/jpeg", "image/png", "image/webp"].includes(im?.media_type) || typeof im?.data !== "string" || !im.data)
    return fail(400, "image must be {media_type, data(base64)}", { media_type: im?.media_type, hasData: typeof im?.data === "string" });
  if (im.data.length > 5_000_000) return fail(413, "image too large; resize to ~1600px before sending", im.data.length);

  // The closet, with recency: the strongest signal for which of several look-alikes is in the photo.
  const [{ data: items, error: ie }, { data: wears, error: we }] = await Promise.all([
    sb.from("items").select("id,name,brand,colors,layer,material,swatch_hex,categories(name)").eq("status", "active"),
    sb.from("outfit_items").select("item_id,outfits!inner(worn_on)"),
  ]);
  if (ie) return fail(502, `items: ${ie.message}`, ie);
  if (we) return fail(502, `outfits: ${we.message}`, we);

  const today = new Date().toISOString().slice(0, 10);
  const cutoff = new Date(Date.now() - 30 * 86400000).toISOString().slice(0, 10);
  const stat = new Map<number, { last: string | null; n30: number }>();
  for (const w of wears ?? []) {
    const d = (w as any).outfits?.worn_on as string | undefined; if (!d) continue;
    const s = stat.get(w.item_id) ?? { last: null, n30: 0 };
    if (!s.last || d > s.last) s.last = d;
    if (d >= cutoff) s.n30++;
    stat.set(w.item_id, s);
  }
  const daysAgo = (d: string) => Math.round((Date.parse(today) - Date.parse(d)) / 86400000);
  const byId = new Map<number, any>();
  const closet = (items ?? []).map((it: any) => {
    byId.set(it.id, it);
    const s = stat.get(it.id);
    const last = s?.last ? `${s.last} (${daysAgo(s.last)} days ago)` : "never";
    return `#${it.id} | ${it.name} | ${it.brand ?? "-"} | ${(it.colors ?? []).join("/") || "-"} | ${it.layer ?? "-"} | ${it.categories?.name ?? "-"} | ${it.material ?? "-"} | ${last} | ${s?.n30 ?? 0}`;
  }).join("\n");

  let ar: Response;
  try {
    ar = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 4096,
        system: systemPrompt(closet, today),
        messages: [{ role: "user", content: [
          { type: "image", source: { type: "base64", media_type: im.media_type, data: im.data } },
          { type: "text", text: "List the visible garments and their closet candidates. JSON only." },
        ] }],
      }),
    });
  } catch (e) { return fail(502, "could not reach the Claude API", String(e)); }
  const aj = await ar.json().catch(() => null);
  if (!ar.ok) return fail(502, `Claude API ${ar.status}: ${aj?.error?.message ?? "unknown"}`, aj);
  const text = (aj?.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("");
  const usage = aj?.usage ?? {};
  if (aj?.stop_reason === "max_tokens")
    return fail(502, "identification was cut off; try again or pick by hand", { stop_reason: aj.stop_reason, usage, head: text.slice(0, 600), tail: text.slice(-300) });
  let out: any;
  try { out = parseJson(text); }
  catch (e) { return fail(502, "could not parse identification", { stop_reason: aj?.stop_reason, usage, parse: String(e), head: text.slice(0, 600), tail: text.slice(-300) }); }

  // Tidy: known slots, candidates that exist in the closet, no duplicates, at most 3, with recency attached for display.
  const garments = (Array.isArray(out?.garments) ? out.garments : []).map((g: any) => {
    const seen = new Set<number>();
    const candidates = (Array.isArray(g?.candidates) ? g.candidates : []).map((c: any) => {
      const id = Number(c?.item_id);
      if (!byId.has(id) || seen.has(id)) return null;
      seen.add(id);
      const s = stat.get(id);
      return { item_id: id, confidence: CONF.includes(c?.confidence) ? c.confidence : "low", why: typeof c?.why === "string" ? c.why.slice(0, 160) : "",
               last_worn: s?.last ?? null, wears_30d: s?.n30 ?? 0 };
    }).filter(Boolean).slice(0, 3);
    return { slot: SLOTS.includes(g?.slot) ? g.slot : "accessory", seen: typeof g?.seen === "string" ? g.seen.slice(0, 120) : "", candidates };
  }).filter((g: any) => g.seen || g.candidates.length);

  console.log(`identify-outfit ok: stop_reason=${aj?.stop_reason} in=${usage.input_tokens} out=${usage.output_tokens} closet=${byId.size} garments=${garments.length}`);
  return json({ garments, model: MODEL, stop_reason: aj?.stop_reason ?? null, usage: { input_tokens: usage.input_tokens ?? null, output_tokens: usage.output_tokens ?? null }, closet_size: byId.size });
});
