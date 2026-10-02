import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../theme.dart';

/// One choice on "What will you use BeauTap for?" (sign-up and welcome).
class RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final String tag;
  final bool selected;
  final VoidCallback onTap;

  const RoleCard({
    super.key,
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.tag,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary.withValues(alpha: 0.06) : AppColors.card,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: selected ? AppColors.primary : AppColors.borderStrong,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: selected ? AppColors.primary.withValues(alpha: 0.12) : AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: selected ? AppColors.primary : AppColors.textTertiary, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? AppColors.primary : AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                const SizedBox(height: 6),
                Text(tag,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: selected ? AppColors.primary : AppColors.textTertiary,
                    )),
              ]),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(
              selected ? TablerIcons.circle_check_filled : TablerIcons.circle,
              color: selected ? AppColors.primary : AppColors.borderStrong,
              size: 22,
            ),
          ]),
        ),
      ),
    );
  }
}

/// The two account types, worded the same everywhere.
class RoleChoice extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;
  const RoleChoice({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      RoleCard(
        icon: TablerIcons.calendar_heart,
        label: 'I want to book beauty services',
        subtitle: 'Find hairdressers, nail techs, makeup artists, barbers and more near you, and book them. Free.',
        tag: 'Client account',
        selected: value == 'client',
        onTap: () => onChanged('client'),
      ),
      const SizedBox(height: AppSpacing.md),
      RoleCard(
        icon: TablerIcons.scissors,
        label: 'I do beauty work and want clients',
        subtitle: 'For hairdressers, braiders, nail techs, makeup artists, barbers, lash techs and salons. '
            'Show your work, set your prices and take bookings.',
        tag: 'Beauty pro account',
        selected: value == 'provider',
        onTap: () => onChanged('provider'),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        'Only want to book? Choose the first one. Each email can only be one type, '
        'so a pro who also books uses the pro account.',
        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
      ),
    ]);
  }
}
