import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/firebase_config.dart';
import '../router.dart';
import '../supabase_client.dart';
import '../theme.dart';

/// Stage 22: FCM push notifications (basic).
///
/// Inert until [firebaseConfigured] is true in firebase_config.dart —
/// safe to ship before the Firebase project exists.
class PushService {
  static bool _initialized = false;
  static const _promptCountKey = 'push_prompt_count';
  static const _maxPrompts = 3;

  /// Call once after login, from a screen with a valid [BuildContext].
  /// Shows the custom permission prompt (max 3 times), registers the
  /// device token, and wires up tap-to-open routing.
  static Future<void> maybeInit(BuildContext context) async {
    if (!firebaseConfigured || _initialized) return;
    if (supabase.auth.currentUser == null) return;
    _initialized = true;

    try {
      await Firebase.initializeApp(
        options: kIsWeb ? webFirebaseOptions : androidFirebaseOptions,
      );

      final messaging = FirebaseMessaging.instance;
      var settings = await messaging.getNotificationSettings();

      if (settings.authorizationStatus == AuthorizationStatus.notDetermined) {
        final prefs = await SharedPreferences.getInstance();
        final promptCount = prefs.getInt(_promptCountKey) ?? 0;
        if (promptCount >= _maxPrompts) return;

        // Roadmap: custom dialog with a 1-2s delay after login
        await Future.delayed(const Duration(seconds: 2));
        if (!context.mounted) return;

        final wantsPush = await _showPermissionDialog(context);
        await prefs.setInt(_promptCountKey, promptCount + 1);
        if (wantsPush != true) return;

        settings = await messaging.requestPermission();
      }

      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        return;
      }

      await _registerToken(messaging);
      messaging.onTokenRefresh.listen(_saveToken);

      // Tap on a notification (background → opened)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleTap);
      final initial = await messaging.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (e) {
      debugPrint('PushService init failed: $e');
    }
  }

  static Future<void> _registerToken(FirebaseMessaging messaging) async {
    final token = kIsWeb
        ? await messaging.getToken(vapidKey: webVapidKey)
        : await messaging.getToken();
    if (token != null) await _saveToken(token);
  }

  static Future<void> _saveToken(String token) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await supabase.from('profiles').update({'fcm_token': token}).eq('id', uid);
    } catch (e) {
      debugPrint('PushService token save failed: $e');
    }
  }

  static void _handleTap(RemoteMessage message) {
    final route = message.data['route'];
    if (route is String && route.startsWith('/')) {
      appRouter.go(route);
    }
  }

  /// Clears the stored token on logout so a shared device stops
  /// receiving this user's notifications.
  static Future<void> clearToken() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null || !firebaseConfigured) return;
    try {
      await supabase.from('profiles').update({'fcm_token': null}).eq('id', uid);
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Future<bool?> _showPermissionDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.notifications_active_rounded,
              color: AppColors.primary, size: 32),
        ),
        title: const Text('Stay in the Loop'),
        content: const Text(
          'Get notified the moment your booking is confirmed, when messages arrive, and an hour before every appointment.',
          style: TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
            child: const Text('Enable Notifications'),
          ),
        ],
      ),
    );
  }
}
