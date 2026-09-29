import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Google sign-in. The website redirects back to itself; the phone app opens
/// Google in the browser, which sends the person back to the app through the
/// `com.beautap.app://login-callback` link.
class GoogleAuth {
  static const appRedirect = 'com.beautap.app://login-callback';

  /// True while the phone app is waiting to come back from Google.
  static bool pending = false;

  /// [userType] is set when signing up, so the new account gets the right role.
  static Future<void> start({String? userType}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userType != null) await prefs.setString('pending_user_type', userType);
    pending = !kIsWeb;
    await supabase.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: kIsWeb ? Uri.base.origin : appRedirect,
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// First Google sign-in from the login screen: make a client profile.
  static Future<void> ensureProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await supabase.from('profiles').select('id').eq('id', user.id).maybeSingle();
      if (existing != null) return;
      await supabase.from('profiles').insert({
        'id': user.id,
        'full_name': user.userMetadata?['full_name'] ?? user.userMetadata?['name'] ?? '',
        'user_type': 'client',
      });
    } catch (_) {}
  }
}
