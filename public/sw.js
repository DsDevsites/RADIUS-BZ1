const CACHE = "radius-bz1-v1";
self.addEventListener("install", event => { event.waitUntil(caches.open(CACHE).then(cache => cache.addAll(["/", "/manifest.webmanifest", "/icons/icon.svg"]))); self.skipWaiting(); });
self.addEventListener("activate", event => { event.waitUntil(self.clients.claim()); });
self.addEventListener("fetch", event => { if (event.request.method !== "GET" || new URL(event.request.url).origin !== self.location.origin) return; event.respondWith(fetch(event.request).catch(() => caches.match(event.request).then(response => response || caches.match("/")))); });
