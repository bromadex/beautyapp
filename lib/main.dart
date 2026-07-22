import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart';
import 'supabase_client.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: 'https://suxohsmcgjzzllmyesgt.supabase.co',
    anonKey: 'sb_publishable_uMr64oTLkPo4HJGQFos_IQ_BFm7CHTN',
  );

  await _applyPendingOAuthUserType();

  runApp(const BeautyApp());
}

Future<void> _applyPendingOAuthUserType() async {
  final prefs = await SharedPreferences.getInstance();
  final pendingType = prefs.getString('pending_user_type');
  if (pendingType == null) return;

  await prefs.remove('pending_user_type');

  final user = supabase.auth.currentUser;
  if (user == null) return;

  try {
    await supabase.from('profiles').upsert({
      'id': user.id,
      'full_name': user.userMetadata?['full_name'] ??
          user.userMetadata?['name'] ??
          user.email?.split('@').first ??
          '',
      'user_type': pendingType,
    }, onConflict: 'id');

    if (pendingType == 'provider') {
      await supabase.from('provider_profiles').upsert({
        'provider_id': user.id,
        'bio': '',
      }, onConflict: 'provider_id');
    }

    await supabase.auth.updateUser(UserAttributes(
      data: {'user_type': pendingType},
    ));
  } catch (_) {}
}

class BeautyApp extends StatelessWidget {
  const BeautyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'BeauTap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      routerConfig: appRouter,
      scrollBehavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
    );
  }
}
