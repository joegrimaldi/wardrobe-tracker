# Wardrobe

Phone-first outfit log. One static page (`index.html`) on GitHub Pages, data in Supabase.

- **Live:** https://joegrimaldi.github.io/wardrobe-tracker/ (Pages serves `main`, repo root)
- **Supabase project:** `sobshyactzxhtsayemkj`. The browser uses the publishable key only; RLS grants `authenticated` everything and `anon` nothing.
- **Tabs:** Today (log / wear again / edit) · Trip (Days · Pack) · Closet (needs-attention filters → Item page with photos, looks, inline edits).

## Rules the code follows
- Logging must take under 15 seconds. No ratings, no required fields.
- The existing outfit for a date/slot is **always fetched before showing or saving** (`fetchOutfit`). Saving replaces the item list; an empty list is never saved.
- Wear counts, last-worn and cost-per-wear are derived from `outfit_items`, never stored.
- `occasion_items` is the plan; it is never counted as a wear.
- Prices: receipt/manual `$X`, estimate `~$X`, null "no price".
- Pack-list ticks live in `localStorage` (`pack:<trip_id>`), per device, by design.
- Photos are never deleted from the bucket; changing the cover repoints `items.photo_ref` and re-samples `swatch_hex` (`swatch_source = 'photo'`).
- Selfie recognition is a seam only: `suggestItemsFromPhoto()` returns nothing until an Edge Function with an Anthropic key exists.

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
