// Push service worker for the web build (phase 3 of the plan: the iPhone
// players get pushes). It needs no Firebase script: Firebase Cloud
// Messaging delivers each push as a JSON payload with the server's
// notification (title, body) and data (link), and this worker shows it.
// Safari on iOS requires every push to show a notification.
//
// It lives in /push/ so its scope never meets the page's own. A tap opens
// the app at its base address with ?push=<link>, which the app reads as
// the push it came from.

self.addEventListener('install', function () {
  self.skipWaiting();
});

self.addEventListener('activate', function (event) {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('push', function (event) {
  var payload = {};
  try {
    payload = event.data ? event.data.json() : {};
  } catch (e) {
    payload = {};
  }
  var note = payload.notification || {};
  var data = payload.data || {};
  var options = {
    body: note.body || '',
    icon: '../icons/Icon-192.png',
    badge: '../icons/Icon-192.png',
    lang: 'ar',
    dir: 'rtl',
    data: { link: data.link || '' }
  };
  event.waitUntil(
    self.registration.showNotification(note.title || '\u0646\u064f\u062e\u0628\u0629', options)
  );
});

self.addEventListener('notificationclick', function (event) {
  event.notification.close();
  var link = (event.notification.data && event.notification.data.link) || '';
  var app = new URL('../', self.registration.scope);
  if (link) {
    app.searchParams.set('push', link);
  }
  event.waitUntil(self.clients.openWindow(app.href));
});
