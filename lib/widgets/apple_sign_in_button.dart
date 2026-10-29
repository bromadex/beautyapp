import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/social_auth.dart';
import '../theme.dart';

/// "Continue with Apple". Shows nothing until Apple sign-in is switched on.
class AppleSignInButton extends StatefulWidget {
  final String label;

  /// Set on the sign-up page so a new account gets the chosen type.
  final String? userType;

  /// See-through white style, for use over a photo.
  final bool onPhoto;

  const AppleSignInButton({super.key, required this.label, this.userType, this.onPhoto = false});

  @override
  State<AppleSignInButton> createState() => _AppleSignInButtonState();
}

class _AppleSignInButtonState extends State<AppleSignInButton> {
  bool _enabled = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    appleSignInEnabled().then((on) {
      if (mounted) setState(() => _enabled = on);
    });
  }

  Future<void> _start() async {
    setState(() => _loading = true);
    try {
      await SocialAuth.start(provider: OAuthProvider.apple, userType: widget.userType);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e is AuthException ? e.message : 'Could not open Apple sign-in. Try again.'),
          backgroundColor: AppColors.error,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_enabled) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.onPhoto ? 10 : 12),
      child: FilledButton.icon(
        onPressed: _loading ? null : _start,
        icon: const Icon(TablerIcons.brand_apple_filled, size: 22),
        label: Text(_loading ? 'Opening Apple…' : widget.label),
        style: widget.onPhoto
            ? FilledButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(54),
                shape: StadiumBorder(side: BorderSide(color: Colors.white.withValues(alpha: 0.45))),
              )
            : FilledButton.styleFrom(
                backgroundColor: AppColors.isDark ? Colors.white : Colors.black,
                foregroundColor: AppColors.isDark ? Colors.black : Colors.white,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              ),
      ),
    );
  }
}
