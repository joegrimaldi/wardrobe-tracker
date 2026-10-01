# Wardrobe

Phone-first outfit log. One static page (`index.html`) on GitHub Pages, data in Supabase.

- **Live:** https://joegrimaldi.github.io/wardrobe-tracker/ (Pages serves `main`, repo root)
- **Supabase project:** `sobshyactzxhtsayemkj`. The browser uses the publishable key only; RLS grants `authenticated` everything and `anon` nothing.
- **Tabs:** Today (log / wear again / edit) · Trip (Days · Pack) · Closet (needs-attention filters → Item page with photos, looks, inline edits).

## Rules the code follows
- Logging must take under 15 seconds. No ratings, no required fields.
- The day rolls over at 03:33 phone-local time (`DAY_ROLLOVER` in `index.html`), not midnight. Everything the app calls "today" comes from `todayISO()`; the picker's date control still allows any date.
- The existing outfit for a date/slot is **always fetched before showing or saving** (`fetchOutfit`). Saving replaces the item list; an empty list is never saved.
- Wear counts, last-worn and cost-per-wear are derived from `outfit_items`, never stored.
- `occasion_items` is the plan; it is never counted as a wear.
- Closet, picker and Pack groups come from `categories.parent_id` at load time. `GROUP_DEFS` in `index.html` only sets the order and labels; a new top-level category nobody lists there becomes its own group instead of landing in Other.
- Prices: receipt/manual `$X`, estimate `~$X`, null "no price".
- Pack-list ticks live in `localStorage` (`pack:<trip_id>`), per device, by design.
- Photos are never deleted from the bucket; changing the cover repoints `items.photo_ref` and re-samples `swatch_hex` (`swatch_source = 'photo'`).
- Adding an item (`+ Item` on Closet, `+ Add item` when a picker search finds nothing): photo(s) are resized to 1600 px JPEG and sent to the `identify-item` Edge Function, which returns a draft and writes nothing. Joe reviews a prefilled form; nothing is saved until Save. The app never writes `price_source = 'estimate'`: price is a receipt's, typed (`manual`), or blank. Save is ordered and resumable (insert → item photo → labels → cover + swatch → receipt link). `identify-item` only accepts calls from the live origin (CORS), so it cannot be exercised from localhost.
- Selfie recognition is a seam only: `suggestItemsFromPhoto()` returns nothing until an Edge Function with an Anthropic key exists.

## Poor-signal mode
The app opens, shows the plan and accepts an outfit log with no connection. It is not a full offline mode.
- **Shell:** `sw.js` (scope `/wardrobe-tracker/`). `index.html` is network-first with a 3 s timeout, then cache, so a deploy is picked up on the next online open. Pinned supabase-js modules (esm.sh), Google Fonts and the icon are cache-first. Item photos are cached as they are viewed (150 entries). Supabase REST/auth/functions are never handled by the worker.
- **Data:** after every successful load the app saves a snapshot to `localStorage` (`wardrobe:snapshot:v1`). On start the network races a 4 s timeout; if it loses, the snapshot is shown with "Offline · last synced …" and replaced when the network lands.
- **Logging:** every outfit save goes through `logOutfit()`. With no connection, or no answer, the log is parked in `wardrobe:queue:v1` (one entry per date + slot, last write wins), shown as logged, and flushed on `online`, on app open, on returning to the foreground, on a 45 s timer, or by tapping "N logs waiting to sync". `worn_on` is fixed when the log is made. A selfie cannot be parked; the outfit is saved without it.
- **Sign-in:** supabase-js cannot refresh the token offline and then reports no session. The app never asks it at boot: a stored refresh token means signed in. The sign-in screen appears only with no stored session, or after a real `SIGNED_OUT`.
- **Online-only:** + Item, + Photo, Set as cover, field edits and planning are dimmed and say "Needs a connection".
- **Reset:** Closet → "Reset offline cache" unregisters the worker, clears its caches and reloads (sign-in, snapshot and queue are kept).
- **Kill switch:** to remove the worker from every device, replace `sw.js` with:
  ```js
  self.addEventListener('install', () => self.skipWaiting());
  self.addEventListener('activate', e => e.waitUntil((async () => {
    for (const k of await caches.keys()) await caches.delete(k);
    await self.registration.unregister();
    for (const c of await self.clients.matchAll()) c.navigate(c.url);
  })()));
  ```
  Do not just delete `sw.js`: a 404 leaves the installed worker in place.
- The ✓ beside a price means the price itself came from a receipt (`price_source = 'receipt'`).

## Storage layout (`item-photos` bucket)
- Item photos: `wd-<3-digit id>-<slug>-<own|retail|label>[-stamp].jpg`, listed by prefix `wd-080-`.
- Outfit selfies: `outfits/<worn_on>-<slot>.jpg`, path stored in `outfits.photo_ref`.
- `items.photo_ref` may carry a legacy `item-photos/` prefix; the app strips it when building URLs.

## Deploy / roll back
Commit to `main`; Pages redeploys in about a minute. To roll back, revert to the previous commit of `index.html`
(`git revert <sha>` or `git checkout <sha> -- index.html && git commit`).

## Keep-alive
`.github/workflows/keepalive.yml` pings the REST API daily so the free-tier project does not pause after 7 idle days.
It uses the `SUPABASE_PUBLISHABLE_KEY` repo secret if set, otherwise the publishable key already in `index.html`.

## Local testing
Serve the folder (`python3 -m http.server`) and sign in; reads are free, for writes use a throwaway date and delete only what you created.
