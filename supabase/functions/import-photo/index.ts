import { createClient } from "npm:@supabase/supabase-js@2";

// Import a product photo from a public image URL into the item-photos bucket.
// Runs as the signed-in user (their JWT), so storage/RLS rules apply exactly as in the app.
// Body: { item_id: number, image_url: string, kind?: 'retail'|'own'|'label', make_cover?: boolean }

const cors = {
  "Access-Control-Allow-Origin": "https://joegrimaldi.github.io",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (b: unknown, status = 200) =>
  new Response(JSON.stringify(b), { status, headers: { ...cors, "Content-Type": "application/json" } });

const slug = (s: string) =>
  s.normalize("NFKD").replace(/[\u0300-\u036f]/g, "").toLowerCase()
   .replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 60);

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: cors });
  if (req.method !== "POST") return json({ error: "POST only" }, 405);

  const auth = req.headers.get("Authorization") ?? "";
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: auth } },
    auth: { persistSession: false },
  });
  const { data: u } = await sb.auth.getUser();
  if (!u?.user) return json({ error: "not signed in" }, 401);

  let body: any;
  try { body = await req.json(); } catch { return json({ error: "bad json" }, 400); }
  const itemId = Number(body.item_id);
  const imageUrl = String(body.image_url ?? "");
  const kind = ["retail", "own", "label"].includes(body.kind) ? body.kind : "retail";
  const makeCover = body.make_cover !== false;
  if (!Number.isInteger(itemId) || !/^https:\/\//.test(imageUrl)) return json({ error: "item_id and https image_url required" }, 400);

  const { data: item, error: ie } = await sb.from("items").select("id,name,photo_ref,photo_source").eq("id", itemId).single();
  if (ie || !item) return json({ error: "item not found" }, 404);

  const r = await fetch(imageUrl, { headers: { "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", "Accept": "image/avif,image/webp,image/jpeg,image/png,*/*" } });
  const ct = (r.headers.get("content-type") ?? "").split(";")[0].trim();
  if (!r.ok || !ct.startsWith("image/")) return json({ error: `fetch failed: ${r.status} ${ct}` }, 502);
  const bytes = new Uint8Array(await r.arrayBuffer());
  if (bytes.length > 10 * 1024 * 1024) return json({ error: "image over 10 MB" }, 413);
  const ext = ct === "image/png" ? "png" : ct === "image/webp" ? "webp" : "jpg";

  const path = `wd-${String(itemId).padStart(3, "0")}-${slug(item.name)}-${kind}-${Date.now().toString(36)}.${ext}`;
  const { error: ue } = await sb.storage.from("item-photos").upload(path, bytes, { contentType: ct, upsert: false, cacheControl: "3600" });
  if (ue) return json({ error: `upload failed: ${ue.message}` }, 500);

  let cover = false;
  // Retail shots become the cover; own/label shots only when the item has no cover yet.
  if (makeCover && (kind === "retail" || !item.photo_ref)) {
    const { error: pe } = await sb.from("items").update({ photo_ref: path, photo_source: kind === "retail" ? "retailer" : "own_photo" }).eq("id", itemId);
    if (pe) return json({ error: `stored at ${path} but cover update failed: ${pe.message}` }, 500);
    cover = true;
  }
  return json({ path, bytes: bytes.length, content_type: ct, cover });
});
