import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase_client.dart';

/// Google and Apple sign-in. The website redirects back to itself; the phone
/// app opens the sign-in page in the browser, which sends the person back to
/// the app through the `com.beautap.app://login-callback` link.
class SocialAuth {
  static const appRedirect = 'com.beautap.app://login-callback';

  /// True while the phone app is waiting to come back from the browser.
  static bool pending = false;

  /// [userType] is set when signing up, so the new account gets the right role.
  static Future<void> start({OAuthProvider provider = OAuthProvider.google, String? userType}) async {
    final prefs = await SharedPreferences.getInstance();
    if (userType != null) await prefs.setString('pending_user_type', userType);
    await prefs.setBool('signup_choice_made', userType != null);
    pending = !kIsWeb;
    await supabase.auth.signInWithOAuth(
      provider,
      redirectTo: kIsWeb ? Uri.base.origin : appRedirect,
      authScreenLaunchMode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
    );
  }

  /// First sign-in from the login screen: make a client profile.
  static Future<void> ensureProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) return;
    try {
      final existing = await supabase.from('profiles').select('id').eq('id', user.id).maybeSingle();
      if (existing != null) return;
      await supabase.from('profiles').insert({
        'id': user.id,
        'full_name': displayName(user),
        'user_type': 'client',
      });
    } catch (_) {}
  }
}

/// Name from Google or Apple. Apple only shares it on the first sign-in and
/// may hide the email, so fall back to the start of the email.
String displayName(User user) {
  final m = user.userMetadata ?? {};
  final n = (m['full_name'] ?? m['name'] ?? '').toString().trim();
  if (n.isNotEmpty) return n;
  final e = user.email ?? '';
  return e.contains('privaterelay.appleid.com') ? '' : e.split('@').first;
}

/// Apple sign-in stays hidden until it's set up (app_settings apple_sign_in = on).
Future<bool> appleSignInEnabled() async {
  try {
    final row = await supabase.from('app_settings').select('value').eq('key', 'apple_sign_in').maybeSingle();
    return row?['value'] == 'on';
  } catch (_) {
    return false;
  }
}
