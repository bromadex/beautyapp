import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../supabase_client.dart';

const _pendingKey = 'pending_referral_code';

/// Links a new pro to the pro who invited them. If there's no session yet
/// (e.g. email still to confirm), the code is kept and tried again later.
Future<void> applyReferralCode(String code, {BuildContext? context}) async {
  if (supabase.auth.currentSession == null) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingKey, code);
    return;
  }
  try {
    await supabase.rpc('use_referral_code', params: {'p_code': code});
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
  } on PostgrestException catch (e) {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_pendingKey);
    if (context != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Referral code: ${e.message}')));
    }
  } catch (_) {}
}

/// Called when a pro opens their home screen.
Future<void> applyPendingReferral() async {
  final prefs = await SharedPreferences.getInstance();
  final code = prefs.getString(_pendingKey);
  if (code == null || supabase.auth.currentSession == null) return;
  await applyReferralCode(code);
}
