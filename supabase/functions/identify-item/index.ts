import { createClient } from "npm:@supabase/supabase-js@2";

// identify-item: photo(s) of a garment -> a draft item record + receipt candidates + possible duplicates.
// Runs as the signed-in user (their JWT). Writes NOTHING; the app saves after Joe reviews the form.
// Body: { images: [{ media_type: "image/jpeg"|"image/png"|"image/webp", data: "<base64>" }] }  (1-3 images, garment first, labels after)
// Secrets: ANTHROPIC_API_KEY (required), ANTHROPIC_MODEL (optional, default below).

const cors = {
  "Access-Control-Allow-Origin": "https://joegrimaldi.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const MODEL = Deno.env.get("ANTHROPIC_MODEL") ?? "claude-sonnet-5-5";
// Must match the items_location_check constraint in the database (same order).
const LOCATIONS = ["Coat rack", "Shoe rack", "Basket", "Dresser", "Closet", "Cedar chest", "Bureau", "Storage unit"];

function systemPrompt(categories: any[], teams: any[]) {
  return `You identify a single garment or accessory from photos for Joe's wardrobe database. Photo 1 is the item; any further photos are labels/tags.

HARD RULES
- Only report what is visible or legible. Never guess a brand, size, fibre or style code you cannot read. Use null when unsure.
- Name = the vendor's own product name ONLY if printed on a tag or label you can read; otherwise a short plain description (e.g. "Shawl Collar Cardigan"). Then " — <colour>". Never put the brand in the name.
- Team or band fan gear: start the name with the team/band short name (e.g. "Chiefs ...", "Phish ...").
- Never estimate a price. Price comes from receipts or Joe.
- Formality 1 lounge/gym, 2 casual, 3 smart casual, 4 cocktail/tailored, 5 suit & tie.

CATEGORIES (use the id of the most specific fit):
${categories.map((c) => `${c.id}: ${c.path}`).join("\n")}

TEAMS/BANDS (use id only if the item clearly shows this team/band):
${teams.map((t) => `${t.id}: ${t.name} (${t.kind})`).join("\n")}

Return ONLY one JSON object, no prose, no code fences:
{
  "name": string, "brand": string|null, "colour_name": string, "colors": string[],
  "category_id": number|null, "layer": "shirt"|"pants"|"outer"|"shoes"|"accessory"|"other",
  "material": string|null, "size": string|null, "style_code": string|null,
  "formality": 1-5, "weight": "light"|"mid"|"heavy", "season_tags": string[],
  "team_id": number|null, "label_text": string|null,
  "search_terms": string[],
  "confidence": { "<field>": "high"|"medium"|"low" },
  "description": string
}
search_terms: 2-5 distinctive words that would appear on a receipt line for this exact item (style name, style code, garment noun). Do NOT include colour words. description: one sentence of visible details (fabric, closure, pockets, print).`;
}

function parseJson(text: string) {
  const t = text.replace(/```json|```/g, "").trim();
  const s = t.indexOf("{"), e = t.lastIndexOf("}");
  return JSON.parse(t.slice(s, e + 1));
}

const COLOUR_WORDS = new Set(["red","blue","navy","black","white","grey","gray","green","olive","tan","brown","khaki","beige","cream","ivory","natural","camel","stone","sand","yellow","gold","orange","pink","purple","indigo","light","dark"]);
const GENERIC = new Set(["jacket","shirt","pant","pants","trouser","trousers","hoodie","sweater","sweatshirt","coat","tee","jeans","jean","shorts","short","belt","shoe","shoes","overshirt","cardigan","crew","crewneck","long","sleeve","with","and","the","style","mens","classic"]);
const words = (s: string) => new Set((s ?? "").toLowerCase().replace(/[^a-z0-9 ]+/g, " ").split(/\s+/)
  .filter((w) => w.length >= 4 && !GENERIC.has(w) && !COLOUR_WORDS.has(w)));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const key = Deno.env.get("ANTHROPIC_API_KEY");
  if (!key) return json({ error: "ANTHROPIC_API_KEY is not set in Supabase function secrets" }, 503);

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: req.headers.get("Authorization") ?? "" } },
    auth: { persistSession: false },
  });
  const { data: u } = await sb.auth.getUser();
  if (!u?.user) return json({ error: "not signed in" }, 401);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const images = Array.isArray(body.images) ? body.images.slice(0, 3) : [];
  if (!images.length) return json({ error: "at least one image required" }, 400);
  for (const im of images) {
    if (!["image/jpeg", "image/png", "image/webp"].includes(im?.media_type) || typeof im?.data !== "string")
      return json({ error: "images must be {media_type, data(base64)}" }, 400);
    if (im.data.length > 5_000_000) return json({ error: "image too large; resize to ~1600px before sending" }, 413);
  }

  const [{ data: cats }, { data: teams }] = await Promise.all([
    sb.from("categories").select("id,name,parent_id"),
    sb.from("teams").select("id,name,kind"),
  ]);
  const byId = new Map((cats ?? []).map((c: any) => [c.id, c]));
  const categories = (cats ?? []).map((c: any) => ({ id: c.id, path: c.parent_id ? `${byId.get(c.parent_id)?.name} > ${c.name}` : c.name }));

  const ar = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: { "x-api-key": key, "anthropic-version": "2023-06-01", "content-type": "application/json" },
    body: JSON.stringify({
      model: MODEL,
      max_tokens: 1200,
      system: systemPrompt(categories, teams ?? []),
      messages: [{
        role: "user",
        content: [
          ...images.map((im: any) => ({ type: "image", source: { type: "base64", media_type: im.media_type, data: im.data } })),
          { type: "text", text: "Identify this item. JSON only." },
        ],
      }],
    }),
  });
  const aj = await ar.json().catch(() => null);
  if (!ar.ok) return json({ error: `Claude API ${ar.status}: ${aj?.error?.message ?? "unknown"}` }, 502);
  let draft: any;
  try { draft = parseJson((aj.content ?? []).filter((b: any) => b.type === "text").map((b: any) => b.text).join("")); }
  catch { return json({ error: "could not parse identification" }, 502); }

  // Receipt candidates. Brand and style code are strong; other terms must be 4+ chars and not colour words.
  const brand = typeof draft.brand === "string" ? draft.brand.trim() : "";
  const clean = (t: string) => t.trim().replace(/[%_,()]/g, " ");
  const strong = [brand, draft.style_code].filter((t: any) => typeof t === "string" && t.trim().length >= 3).map(clean);
  const weak = (draft.search_terms ?? []).filter((t: any) => typeof t === "string" && t.trim().length >= 4 && !COLOUR_WORDS.has(t.trim().toLowerCase())).map(clean);
  let receipts: any[] = [];
  const terms = [...strong, ...weak];
  if (terms.length) {
    const ors = terms.flatMap((t: string) => [`item_description.ilike.%${t}%`, `retailer.ilike.%${t}%`]).join(",");
    const { data } = await sb.from("acquisitions")
      .select("id,retailer,order_ref,order_date,item_description,unit_price,quantity")
      .is("matched_item_id", null).or(ors).order("order_date", { ascending: false }).limit(60);
    const s = strong.map((t: string) => t.toLowerCase()), w = weak.map((t: string) => t.toLowerCase());
    receipts = (data ?? []).map((r: any) => {
      const hay = `${r.retailer} ${r.item_description}`.toLowerCase();
      const hs = s.filter((t: string) => hay.includes(t)).length, hw = w.filter((t: string) => hay.includes(t)).length;
      return { ...r, score: hs * 3 + hw, strong_hit: hs > 0 };
    }).filter((r: any) => r.strong_hit || r.score >= 2)
      .sort((a: any, b: any) => b.score - a.score).slice(0, 5);
  }

  // Possible duplicates, ranked: distinctive name words in common, same brand, overlapping colour, same category.
  const draftWords = words([draft.name, ...(draft.search_terms ?? []), draft.style_code ?? ""].join(" "));
  const { data: all } = await sb.from("items").select("id,name,brand,category_id,colors,size,photo_ref");
  const b = brand.toLowerCase();
  const cols = new Set((draft.colors ?? []).map((c: string) => c.toLowerCase()));
  const duplicates = (all ?? []).map((it: any) => {
    const iw = words(it.name);
    const nameHits = [...draftWords].filter((w) => iw.has(w)).length;
    const sameBrand = !!b && (it.brand ?? "").toLowerCase().includes(b);
    const colourOverlap = (it.colors ?? []).some((c: string) => cols.has(c.toLowerCase()));
    const sameCat = !!draft.category_id && it.category_id === draft.category_id;
    const hit = (nameHits >= 1 && colourOverlap) || (sameBrand && (sameCat || nameHits >= 1));
    return { ...it, score: nameHits * 2 + (sameBrand ? 3 : 0) + (colourOverlap ? 1 : 0) + (sameCat ? 1 : 0), hit };
  }).filter((it: any) => it.hit).sort((x: any, y: any) => y.score - x.score).slice(0, 5)
    .map(({ hit, ...rest }: any) => rest);

  return json({ draft, receipts, duplicates, locations: LOCATIONS, model: MODEL });
});
