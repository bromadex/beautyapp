import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme.dart';

/// The privacy policy and account-deletion pages are plain web pages, so
/// they also work for Google Play and people who don't have the app.
const _site = 'https://beautyapp-swart.vercel.app';

Uri legalUrl(String path) => Uri.parse('${kIsWeb ? Uri.base.origin : _site}$path');

Future<void> openPrivacyPolicy() =>
    launchUrl(legalUrl('/privacy'), mode: LaunchMode.externalApplication);

/// "By continuing you agree to our Privacy Policy." with the link tappable.
class PrivacyNotice extends StatelessWidget {
  final String lead;
  const PrivacyNotice({super.key, this.lead = 'By creating an account you agree to our '});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: lead,
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
        children: [
          TextSpan(
            text: 'Privacy Policy',
            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
            recognizer: TapGestureRecognizer()..onTap = openPrivacyPolicy,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }
}
