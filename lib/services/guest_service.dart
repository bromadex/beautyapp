import 'package:flutter/material.dart';
import '../supabase_client.dart';

/// Browse-and-book without an account. Uses Supabase anonymous sign-in; the
/// guest can later add an email + password to keep the same account.
class GuestService {
  static bool get isGuest => supabase.auth.currentUser?.isAnonymous ?? false;

  static Future<bool> continueAsGuest(BuildContext context) async {
    try {
      await supabase.auth.signInAnonymously(data: {'user_type': 'client', 'full_name': 'Guest'});
      return true;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Guest mode is unavailable right now. Please create a free account.')),
        );
      }
      return false;
    }
  }
}
