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
  apiKey: 'REPLACE_ME',
  appId: 'REPLACE_ME',
  messagingSenderId: 'REPLACE_ME',
  projectId: 'REPLACE_ME',
  storageBucket: 'REPLACE_ME',
);

const FirebaseOptions webFirebaseOptions = FirebaseOptions(
  apiKey: 'REPLACE_ME',
  appId: 'REPLACE_ME',
  messagingSenderId: 'REPLACE_ME',
  projectId: 'REPLACE_ME',
  authDomain: 'REPLACE_ME.firebaseapp.com',
  storageBucket: 'REPLACE_ME',
);
