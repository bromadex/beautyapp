import 'package:flutter/material.dart';
import '../theme.dart';

class TravelModeSheet extends StatelessWidget {
  final bool isProvider;
  const TravelModeSheet({super.key, required this.isProvider});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Who is travelling?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Select the arrangement you agreed on with the other party.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xxl),
            _ModeButton(
              icon: Icons.directions_walk_rounded,
              iconColor: AppColors.primary,
              title: 'Provider goes to Client',
              subtitle: 'The stylist travels to the client\'s location',
              value: 'provider_to_client',
            ),
            const SizedBox(height: AppSpacing.md),
            _ModeButton(
              icon: Icons.store_rounded,
              iconColor: AppColors.secondary,
              title: 'Client goes to Provider',
              subtitle: 'The client travels to the salon / provider\'s place',
              value: 'client_to_provider',
            ),
            const SizedBox(height: AppSpacing.md),
            _ModeButton(
              icon: Icons.location_on_rounded,
              iconColor: AppColors.info,
              title: 'Fixed Location (Salon)',
              subtitle:
                  'Provider has a fixed address — no live tracking needed',
              value: 'fixed_location',
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String value;

  const _ModeButton({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => Navigator.pop(context, value),
      style: OutlinedButton.styleFrom(
        padding: AppSpacing.cardPadding,
        alignment: Alignment.centerLeft,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, size: 24, color: iconColor),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(subtitle,
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
