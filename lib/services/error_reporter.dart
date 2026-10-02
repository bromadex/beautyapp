import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../router.dart';
import '../supabase_client.dart';

/// Sends app crashes and errors to BeauTap (Admin → App errors), so problems
/// show up before users complain. Bad-connection errors are left out: they're
/// normal on mobile data and would drown out real bugs.
class ErrorReporter {
  static const appVersion = '1.0.0';

  static final _sentThisSession = <String>{};
  static String? _device;

  static const _ignore = [
    'SocketException',
    'ClientException',
    'Failed host lookup',
    'Connection closed',
    'Connection reset',
    'Connection refused',
    'Network is unreachable',
    'XMLHttpRequest error',
    'TimeoutException',
    'Failed to fetch',
    'HandshakeException',
    'NetworkImageLoadException',
    'HTTP request failed, statusCode',
    'AuthRetryableFetchException',
  ];

  static void install() {
    final previous = FlutterError.onError;
    FlutterError.onError = (details) {
      previous?.call(details);
      report(details.exception, details.stack, context: details.context?.toString());
    };
    PlatformDispatcher.instance.onError = (error, stack) {
      report(error, stack);
      return true;
    };
  }

  static Future<void> report(Object error, StackTrace? stack, {String? context}) async {
    try {
      final message = '${context != null ? '$context: ' : ''}$error';
      if (_ignore.any(message.contains)) return;
      // Once per session per error is enough; the server counts repeats.
      final key = message.length > 200 ? message.substring(0, 200) : message;
      if (!_sentThisSession.add(key)) return;

      String? route;
      try {
        route = appRouter.routerDelegate.currentConfiguration.uri.path;
      } catch (_) {}

      await supabase.rpc('log_app_error', params: {
        'p_message': message,
        'p_stack': stack?.toString(),
        'p_route': route,
        'p_platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'p_app_version': appVersion,
        'p_device': await _deviceId(),
      });
    } catch (_) {
      // Never let error reporting cause another error.
    }
  }

  static Future<String> _deviceId() async {
    if (_device != null) return _device!;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('device_id');
    if (id == null) {
      final r = Random.secure();
      id = List.generate(16, (_) => r.nextInt(16).toRadixString(16)).join();
      await prefs.setString('device_id', id);
    }
    return _device = id;
  }
}
