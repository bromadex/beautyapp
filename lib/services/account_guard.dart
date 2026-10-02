import 'package:flutter/material.dart';

import '../router.dart';
import '../supabase_client.dart';

/// Signs out an account that BeauTap has suspended. The database already
/// blocks new sign-ins and ends sessions; this catches an app that was
/// already open.
class AccountGuard {
  /// Set when we just signed someone out, so the login page can say why.
  static bool justSuspended = false;

  /// Also sends a new Google/Apple account to finish signing up.
  /// Returns true if it moved the person to another page.
  static Future<bool> check() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      final row =
          await supabase.from('profiles').select('is_banned, needs_onboarding').eq('id', uid).maybeSingle();
      if (row?['is_banned'] == true) {
        justSuspended = true;
        await supabase.auth.signOut();
        appRouter.go('/login');
        return true;
      }
      if (row?['needs_onboarding'] == true) {
        if (appRouter.routerDelegate.currentConfiguration.uri.path != '/welcome') appRouter.go('/welcome');
        return true;
      }
    } catch (_) {}
    return false;
  }

  static const message =
      'This account has been suspended for breaking BeauTap\'s rules. If you think this is a mistake, '
      'WhatsApp BeauTap on 0783 778 833.';

  static void showIfSuspended(BuildContext context) {
    if (!justSuspended) return;
    justSuspended = false;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Account suspended'),
        content: const Text(message),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
  }
}
