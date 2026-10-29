import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../glass.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/nav.dart';

/// Shown for a link that doesn't lead anywhere (mistyped, or an old link).
class NotFoundScreen extends StatelessWidget {
  final String path;
  const NotFoundScreen({super.key, required this.path});

  @override
  Widget build(BuildContext context) {
    final signedIn = supabase.auth.currentSession != null;
    return MeshBackground(
      child: Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: GlassCard(
              radius: 28,
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(TablerIcons.map_question, size: 44, color: AppColors.primary),
                const SizedBox(height: 14),
                Text('This page doesn\'t exist', style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: 6),
                Text('The link may be old or mistyped.',
                    textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                GlowButton(
                  label: signedIn ? 'Go to Home' : 'Go to sign in',
                  onPressed: () => context.go(signedIn ? homeTab() : '/login'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
