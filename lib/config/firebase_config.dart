import 'package:firebase_core/firebase_core.dart';

/// Stage 22: Firebase project config for push notifications.
///
/// HOW TO ENABLE PUSH:
/// 1. Create a Firebase project at https://console.firebase.google.com
/// 2. Add an Android app with package name `com.beautap.app` and a Web app
/// 3. Copy the values from the Firebase console into the options below
///    (Project Settings → General → Your apps → SDK setup and configuration)
/// 4. Flip [firebaseConfigured] to true
/// 5. For web push, also set [webVapidKey]
///    (Project Settings → Cloud Messaging → Web Push certificates)
const bool firebaseConfigured = false;

const String webVapidKey = 'REPLACE_WITH_VAPID_KEY';

const FirebaseOptions androidFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyASNCnhMtJH1Mrmk81iJ2506HPydEc_Dzg',
  appId: '1:549119684234:android:14bc982590154d4e9a0773',
  messagingSenderId: '549119684234',
  projectId: 'beautap-6752c',
  storageBucket: 'beautap-6752c.firebasestorage.app',
);

const FirebaseOptions webFirebaseOptions = FirebaseOptions(
  apiKey: 'AIzaSyDrSu_-ZcWYyANafTUaOHdJUVnPp_QRIrI',
  appId: '1:549119684234:web:2b9f1bc5bbed1e609a0773',
  messagingSenderId: '549119684234',
  projectId: 'beautap-6752c',
  authDomain: 'beautap-6752c.firebaseapp.com',
  storageBucket: 'beautap-6752c.firebasestorage.app',
  measurementId: 'G-GYVQ9J3726',
);
