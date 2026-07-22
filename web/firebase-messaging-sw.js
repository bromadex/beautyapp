/**
 * Stage 22: Firebase Messaging service worker (web push).
 * Inactive until the Firebase config below is filled in — fill it with the
 * same values as lib/config/firebase_config.dart (web options), then
 * rebuild/redeploy the web app.
 */
/* eslint-disable no-undef */
const FIREBASE_CONFIGURED = false;

if (FIREBASE_CONFIGURED) {
  importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-app-compat.js');
  importScripts('https://www.gstatic.com/firebasejs/10.12.0/firebase-messaging-compat.js');

  firebase.initializeApp({
    apiKey: 'AIzaSyDrSu_-ZcWYyANafTUaOHdJUVnPp_QRIrI',
    appId: '1:549119684234:web:2b9f1bc5bbed1e609a0773',
    messagingSenderId: '549119684234',
    projectId: 'beautap-6752c',
    authDomain: 'beautap-6752c.firebaseapp.com',
    storageBucket: 'beautap-6752c.firebasestorage.app',
  });

  const messaging = firebase.messaging();

  messaging.onBackgroundMessage((payload) => {
    const title = payload.notification?.title ?? 'BeauTap';
    self.registration.showNotification(title, {
      body: payload.notification?.body ?? '',
      icon: '/icons/Icon-192.png',
      data: payload.data ?? {},
    });
  });
}
