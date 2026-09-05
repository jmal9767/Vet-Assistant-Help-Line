/*
 * Temporary retirement worker for the former PWA at this exact origin/scope.
 * Nothing in the current site registers a service worker. Keep this file only
 * long enough to replace previously installed vahl workers and clear their
 * obsolete cached intake/operator pages.
 */
"use strict";

self.addEventListener("install", (event) => {
  event.waitUntil(self.skipWaiting());
});

self.addEventListener("activate", (event) => {
  event.waitUntil((async () => {
    const cacheNames = await caches.keys();
    await Promise.all(
      cacheNames
        .filter((name) => name === "vahl-v1" || name.startsWith("vahl-"))
        .map((name) => caches.delete(name))
    );

    await self.registration.unregister();

    const windows = await self.clients.matchAll({
      type: "window",
      includeUncontrolled: true
    });
    await Promise.all(windows.map((client) => client.navigate(client.url)));
  })());
});
