import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../theme.dart';
import 'ui.dart';

/// Explains why BeauTap wants a permission before the phone asks, so people
/// know what they're agreeing to. Returns true if they want to go ahead.
class PermissionExplainer {
  static Future<bool> show(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    List<String> points = const [],
    String allowLabel = 'Continue',
    String laterLabel = 'Not now',
  }) async {
    final ok = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SheetScroll(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                  child: Icon(icon, color: AppColors.primary, size: 30),
                ),
              ),
              const SizedBox(height: 16),
              Text(title, textAlign: TextAlign.center, style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(body,
                  textAlign: TextAlign.center,
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.45)),
              if (points.isNotEmpty) ...[
                const SizedBox(height: 16),
                for (final p in points)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(TablerIcons.circle_check, size: 18, color: AppColors.success),
                      const SizedBox(width: 10),
                      Expanded(child: Text(p, style: const TextStyle(fontSize: 14, height: 1.4))),
                    ]),
                  ),
              ],
              const SizedBox(height: 16),
              FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(allowLabel)),
              const SizedBox(height: 4),
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(laterLabel)),
            ]),
          ),
        ),
      ),
    );
    return ok == true;
  }
}
