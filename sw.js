// UsagiDB Service Worker — minimal background-sync skeleton.
//
// Pattern:
//   1. The page enqueues failed sync packets to localStorage under
//      `usagidb_outbox` (a JSON array of `{url, body}`).
//   2. When the page comes online, it `registration.sync.register('usagidb')`.
//   3. This SW handles the `sync` event by draining the outbox via fetch().
//
// Only Chromium browsers support the Background Sync API; on others the page
// falls back to a `window.online` listener that does the same drain inline.

const OUTBOX_KEY = "usagidb_outbox";

self.addEventListener("install", () => {
  self.skipWaiting();
});

self.addEventListener("activate", (event) => {
  event.waitUntil(self.clients.claim());
});

// Background-sync drain.
self.addEventListener("sync", (event) => {
  if (event.tag !== "usagidb") return;
  event.waitUntil(drainOutbox());
});

// On-demand drain triggered by a postMessage from the page.
self.addEventListener("message", (event) => {
  if (event.data && event.data.kind === "drain") {
    event.waitUntil(drainOutbox());
  }
});

async function drainOutbox() {
  // Service workers don't share localStorage with the page; we ask the page
  // for the outbox via postMessage, drain, then ask it to clear.
  const clients = await self.clients.matchAll({ includeUncontrolled: true });
  if (!clients.length) return;
  const client = clients[0];
  const outbox = await requestOutbox(client);
  if (!outbox || !outbox.length) return;
  let sent = 0;
  for (const item of outbox) {
    try {
      const res = await fetch(item.url, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: item.body,
      });
      if (res.ok) sent++;
    } catch (err) {
      // Stay queued — the next sync event will retry.
    }
  }
  client.postMessage({ kind: "outbox-drained", sent });
}

function requestOutbox(client) {
  return new Promise((resolve) => {
    const channel = new MessageChannel();
    channel.port1.onmessage = (e) => resolve(e.data && e.data.outbox);
    client.postMessage({ kind: "request-outbox" }, [channel.port2]);
  });
}
