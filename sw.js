/* Wardrobe service worker: lets the app open with no signal.
   - The app shell (index.html) is NETWORK-FIRST with a 3 s timeout, then cache.
     Never cache-first: that would pin Joe to a stale build after a deploy.
   - Immutable static assets (pinned supabase-js modules on esm.sh, Google Fonts,
     the icon) are cache-first.
   - Item photos from the public storage bucket are cached as they are viewed.
   - Supabase REST, auth, functions and storage API calls are NEVER handled or
     cached here. Data caching lives in the app (snapshot + write queue). */
const VERSION = 'v1';
const SHELL = 'wardrobe-shell-' + VERSION;
const PHOTOS = 'wardrobe-photos-' + VERSION;
const SCOPE = self.registration.scope;
const SHELL_URL = new URL('index.html', SCOPE).href;
const STATIC_HOSTS = ['esm.sh', 'fonts.googleapis.com', 'fonts.gstatic.com'];
const PHOTO_PATH = '/storage/v1/object/public/item-photos/';
const PHOTO_MAX = 150;          // entries; roughly 20-50 MB of 1600 px JPEG/WebP
const NET_TIMEOUT = 3000;

const timeout = (p, ms) => new Promise((res, rej) => {
  const t = setTimeout(() => rej(new Error('timeout')), ms);
  p.then(v => { clearTimeout(t); res(v); }, e => { clearTimeout(t); rej(e); });
});
const keep = (e, p) => { try { e.waitUntil(p); } catch (_) {} };

const ICON_URL = new URL('apple-touch-icon.png?v=2', SCOPE).href;
/* Make sure the shell and icon are in the cache. Runs at install, and again whenever
   the page checks in: a revived registration (after "Reset offline cache", or a browser
   that cleared the cache but kept the worker) never gets a second install event. */
async function ensureShell(force) {
  const cache = await caches.open(SHELL);
  for (const u of [SHELL_URL, ICON_URL]) {
    try {
      if (!force && await cache.match(u)) continue;
      const r = await fetch(u, { cache: 'reload' });
      if (r.ok) await cache.put(u, r);
    } catch (_) {}
  }
}
self.addEventListener('install', e => {
  e.waitUntil(ensureShell(true).then(() => self.skipWaiting()));
});

self.addEventListener('activate', e => {
  e.waitUntil((async () => {
    for (const k of await caches.keys()) if (k.startsWith('wardrobe-') && k !== SHELL && k !== PHOTOS) await caches.delete(k);
    await self.clients.claim();
  })());
});

/* The page tells us which static files it actually loaded (the first visit is
   not controlled by the worker yet, so those requests never passed through here). */
self.addEventListener('message', e => {
  const d = e.data || {};
  if (d.type !== 'precache' || !Array.isArray(d.urls)) return;
  keep(e, (async () => {
    await ensureShell(false);
    const cache = await caches.open(SHELL);
    for (const u of d.urls) {
      try {
        if (!STATIC_HOSTS.includes(new URL(u).hostname)) continue;
        if (await cache.match(u, { ignoreVary: true })) continue;
        const r = await fetch(u, { mode: 'cors' });
        if (r.ok) await cache.put(u, r);
      } catch (_) {}
    }
  })());
});

self.addEventListener('fetch', e => {
  const req = e.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  const inScope = url.href.startsWith(SCOPE);
  const isApp = url.pathname === new URL(SCOPE).pathname || url.pathname === new URL(SHELL_URL).pathname;
  if (req.mode === 'navigate' && inScope && isApp) return e.respondWith(shell(e));
  if (url.origin === self.location.origin && inScope) {
    if (url.pathname.endsWith('/sw.js')) return;
    return e.respondWith(sameOrigin(e));
  }
  if (STATIC_HOSTS.includes(url.hostname)) return e.respondWith(cacheFirst(req));
  if (url.hostname.endsWith('.supabase.co') && url.pathname.includes(PHOTO_PATH)) return e.respondWith(photo(e));
  // Anything else (Supabase REST / auth / functions / storage API) goes straight to the network.
});

async function shell(e) {
  const cache = await caches.open(SHELL);
  const net = fetch(SHELL_URL, { cache: 'no-store' }).then(async r => {
    if (r.ok) await cache.put(SHELL_URL, r.clone());
    return r;
  });
  keep(e, net.catch(() => {}));          // a slow response still refreshes the cache for next time
  try {
    const r = await timeout(net, NET_TIMEOUT);
    if (r.ok) return r;
    throw new Error('bad status');
  } catch (_) {
    const hit = await cache.match(SHELL_URL);
    if (hit) return hit;
    return net.catch(() => new Response('<h1>Offline</h1><p>Open Wardrobe once with a connection first.</p>',
      { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } }));
  }
}

async function sameOrigin(e) {
  const req = e.request, cache = await caches.open(SHELL);
  const net = fetch(req).then(async r => { if (r.ok) await cache.put(req.url, r.clone()); return r; });
  keep(e, net.catch(() => {}));
  try { const r = await timeout(net, NET_TIMEOUT); if (r.ok) return r; throw new Error('bad status'); }
  catch (_) { return (await cache.match(req.url, { ignoreVary: true })) || net; }
}

async function cacheFirst(req) {
  const cache = await caches.open(SHELL);
  const hit = await cache.match(req.url, { ignoreVary: true });
  if (hit) return hit;
  const res = await fetch(req);
  if (res.ok) cache.put(req.url, res.clone()).catch(() => {});
  return res;
}

async function trim(cache) {
  const keys = await cache.keys();
  for (let i = 0; i < keys.length - PHOTO_MAX; i++) await cache.delete(keys[i]);
}

async function photo(e) {
  const req = e.request, url = new URL(req.url);
  if (url.search) return fetch(req);                 // cache-busted requests (swatch sampling) are never stored
  const cache = await caches.open(PHOTOS);
  const hit = await cache.match(req.url, { ignoreVary: true });
  const fromNet = () => fetch(req).then(res => {
    if (res.ok && res.type !== 'opaque') keep(e, cache.put(req.url, res.clone()).then(() => trim(cache)).catch(() => {}));
    return res;
  });
  if (url.pathname.includes(PHOTO_PATH + 'outfits/')) {   // selfies can be replaced in place: prefer the network
    try { return await timeout(fromNet(), NET_TIMEOUT); } catch (err) { if (hit) return hit; throw err; }
  }
  return hit || fromNet();
}
