import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppearanceMode { system, light, dark }

/// The user's Appearance choice, saved on this device.
class Appearance extends ValueNotifier<AppearanceMode> {
  Appearance._() : super(AppearanceMode.system);
  static final instance = Appearance._();

  static const _key = 'appearance_mode';

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = AppearanceMode.values.firstWhere(
        (m) => m.name == prefs.getString(_key),
        orElse: () => AppearanceMode.system,
      );
    } catch (_) {}
  }

  Future<void> set(AppearanceMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, mode.name);
    } catch (_) {}
  }

  bool isDark(Brightness platform) => switch (value) {
        AppearanceMode.dark => true,
        AppearanceMode.light => false,
        AppearanceMode.system => platform == Brightness.dark,
      };
}
