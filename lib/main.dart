import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'router.dart';
import 'supabase_client.dart';
import 'theme.dart';
import 'services/appearance.dart';
import 'services/google_auth.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy();
  // Pages opened on top of others (bookings, chat, settings) get their own
  // address, so refreshing the browser stays on that page.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  await Supabase.initialize(
    url: 'https://suxohsmcgjzzllmyesgt.supabase.co',
    anonKey: 'sb_publishable_uMr64oTLkPo4HJGQFos_IQ_BFm7CHTN',
  );

  await _applyPendingOAuthUserType();
  await Appearance.instance.load();

  // Phone app: coming back from Google in the browser signs the person in
  // without restarting, so set up their account and open their home here.
  if (!kIsWeb) {
    supabase.auth.onAuthStateChange.listen((data) async {
      if (data.event != AuthChangeEvent.signedIn || !GoogleAuth.pending) return;
      GoogleAuth.pending = false;
      await _applyPendingOAuthUserType();
      await GoogleAuth.ensureProfile();
      appRouter.go('/');
    });
  }

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
    // Only a brand-new account takes the role picked on the sign-up page. An
    // existing account keeps its name, bio and role (the database also refuses
    // role changes on accounts older than a day or with bookings).
    final existing =
        await supabase.from('profiles').select('user_type').eq('id', user.id).maybeSingle();
    if (existing == null) {
      await supabase.from('profiles').insert({
        'id': user.id,
        'full_name': user.userMetadata?['full_name'] ??
            user.userMetadata?['name'] ??
            user.email?.split('@').first ??
            '',
        'user_type': pendingType,
      });
    } else if (existing['user_type'] != pendingType) {
      await supabase.from('profiles').update({'user_type': pendingType}).eq('id', user.id);
    }

    final row = await supabase.from('profiles').select('user_type').eq('id', user.id).maybeSingle();
    final actualType = (row?['user_type'] ?? pendingType) as String;

    if (actualType == 'provider') {
      await supabase.from('provider_profiles').upsert(
        {'provider_id': user.id, 'bio': ''},
        onConflict: 'provider_id',
        ignoreDuplicates: true,
      );
    }

    await supabase.auth.updateUser(UserAttributes(
      data: {'user_type': actualType},
    ));
  } catch (_) {}
}

class BeautyApp extends StatefulWidget {
  const BeautyApp({super.key});

  @override
  State<BeautyApp> createState() => _BeautyAppState();
}

class _BeautyAppState extends State<BeautyApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Appearance.instance.addListener(_onAppearance);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    Appearance.instance.removeListener(_onAppearance);
    super.dispose();
  }

  void _onAppearance() => setState(() {});

  // Phone switched between light and dark
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final dark = Appearance.instance.isDark(WidgetsBinding.instance.platformDispatcher.platformBrightness);
    AppColors.isDark = dark;
    return MaterialApp.router(
      title: 'BeauTap',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.current,
      // Colours are read when widgets build, so rebuild everything when the mode flips.
      builder: (context, child) => KeyedSubtree(key: ValueKey(dark), child: child ?? const SizedBox()),
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
