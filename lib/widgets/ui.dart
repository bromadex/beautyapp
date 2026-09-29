import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../theme.dart';

/// Rounded forest square with a "B" and a honey dot — the app mark.
class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 48});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Stack(children: [
        Center(
          child: Text(
            'B',
            style: TextStyle(
              color: Colors.white,
              fontSize: size * 0.5,
              fontWeight: FontWeight.w800,
              height: 1,
              letterSpacing: -1,
            ),
          ),
        ),
        Positioned(
          right: size * 0.2,
          bottom: size * 0.24,
          child: Container(
            width: size * 0.13,
            height: size * 0.13,
            decoration: const BoxDecoration(color: AppColors.secondary, shape: BoxShape.circle),
          ),
        ),
      ]),
    );
  }
}

/// "BeauTap" wordmark.
class Wordmark extends StatelessWidget {
  final double fontSize;
  final bool onDark;
  const Wordmark({super.key, this.fontSize = 22, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(
          text: 'Beau',
          style: TextStyle(color: onDark ? Colors.white : AppColors.textPrimary),
        ),
        TextSpan(
          text: 'Tap',
          style: TextStyle(color: onDark ? AppColors.secondary : AppColors.primary),
        ),
      ]),
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800, letterSpacing: -0.6, height: 1),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;
  const SectionHeader({super.key, required this.title, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(children: [
        Expanded(child: Text(title, style: Theme.of(context).textTheme.titleLarge)),
        if (actionLabel != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            child: Text(actionLabel!),
          ),
      ]),
    );
  }
}

/// Soft tinted notice with an optional tap target.
class SoftBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? message;
  final VoidCallback? onTap;
  final String? actionLabel;
  const SoftBanner({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    this.message,
    this.onTap,
    this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color == AppColors.primary ? AppColors.primarySoft : color.withValues(alpha: 0.12),
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(icon, color: color == AppColors.primary ? AppColors.primary : color, size: 22),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                ],
              ]),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(actionLabel!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ] else if (onTap != null)
              Icon(TablerIcons.chevron_right, color: color),
          ]),
        ),
      ),
    );
  }
}

/// Small rounded label, e.g. status or "Verified".
class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill({super.key, required this.label, this.color = AppColors.primary, this.icon, this.solid = false});

  @override
  Widget build(BuildContext context) {
    final fg = solid ? Colors.white : color;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: AppRadius.xsAll,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: fg)),
      ]),
    );
  }
}

class RatingPill extends StatelessWidget {
  final double rating;
  final int reviews;
  const RatingPill({super.key, required this.rating, required this.reviews});

  @override
  Widget build(BuildContext context) {
    if (reviews == 0) {
      return const Pill(label: 'New', color: AppColors.primary, solid: true);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(TablerIcons.star_filled, size: 16, color: Color(0xFFA8822F)),
      const SizedBox(width: 3),
      Text(rating.toStringAsFixed(1),
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      Text(' ($reviews)', style: const TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
    ]);
  }
}

/// Circle with a photo, or the person's initial on a blush background.
class PersonAvatar extends StatelessWidget {
  final String name;
  final String? url;
  final double size;
  const PersonAvatar({super.key, required this.name, this.url, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    final initial = parts.isEmpty
        ? '?'
        : (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
    final fallback = Center(
      child: Text(initial,
          style: TextStyle(fontSize: size * 0.34, fontWeight: FontWeight.w800, color: AppColors.primary)),
    );
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
      clipBehavior: Clip.antiAlias,
      child: (url != null && url!.isNotEmpty)
          ? Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback)
          : fallback,
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(20)),
            child: Icon(icon, size: 32, color: AppColors.primary),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary), textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ]),
      ),
    );
  }
}

/// Lets other screens pre-select a category on the Browse tab.
class BrowseIntent {
  static final ValueNotifier<String?> category = ValueNotifier(null);
  static final ValueNotifier<String?> group = ValueNotifier(null);
}

/// Built-in icon for a service category (avoids downloading an emoji font on web).
IconData categoryIcon(String? name) => ServiceGroup.of(name)?.icon ?? TablerIcons.sparkles;

class CategoryBadge extends StatelessWidget {
  final String? name;
  final double size;
  const CategoryBadge({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(size * 0.28)),
      child: Icon(categoryIcon(name), size: size * 0.5, color: AppColors.primary),
    );
  }
}

/// The 11 service groups clients browse by. Categories map into them by name
/// until groups live in the database.
class ServiceGroup {
  final String name;
  final IconData icon;
  final List<String> keywords;
  const ServiceGroup(this.name, this.icon, this.keywords);

  bool matches(String? categoryName) {
    final n = (categoryName ?? '').toLowerCase();
    return keywords.any(n.contains);
  }

  static const all = [
    ServiceGroup('Hair', TablerIcons.ripple, ['braid', 'wig', 'natural', 'kid', 'loc', 'relax', 'weave', 'colour', 'color', 'hair', 'cuts & styling']),
    ServiceGroup('Barbering', TablerIcons.scissors, ['barber', 'fade', 'beard', 'shave', 'groom']),
    ServiceGroup('Nails', TablerIcons.hand_finger, ['nail', 'manicure', 'pedicure', 'gel', 'acrylic']),
    ServiceGroup('Lashes & Brows', TablerIcons.eye, ['lash', 'brow', 'microblad']),
    ServiceGroup('Makeup', TablerIcons.brush, ['makeup', 'make-up']),
    ServiceGroup('Skin', TablerIcons.droplet, ['skin', 'facial', 'peel']),
    ServiceGroup('Hair Removal', TablerIcons.feather, ['wax', 'thread', 'sugar', 'removal']),
    ServiceGroup('Body & Spa', TablerIcons.leaf, ['massage', 'spa', 'scrub', 'wrap', 'reflex']),
    ServiceGroup('Glow', TablerIcons.sun_high, ['spray tan', 'whiten', 'glow']),
    ServiceGroup('Body Art', TablerIcons.palette, ['tattoo', 'pierc', 'henna']),
    ServiceGroup('Bridal & Events', TablerIcons.diamond, ['bridal', 'event', 'wedding', 'photoshoot']),
  ];

  static ServiceGroup? of(String? categoryName) {
    final n = (categoryName ?? '').toLowerCase();
    // More specific groups first so "Hair Removal" and "Body Art" are not caught by broader words.
    for (final g in [all[6], all[9], all[10], all[1], all[2], all[3], all[4], all[5], all[7], all[8], all[0]]) {
      if (g.keywords.any(n.contains)) return g;
    }
    return null;
  }
}

/// Bottom tab bar from the design: white bar, gold marker above the active tab.
class BeauNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<({IconData icon, String label, int badge})> items;
  const BeauNavBar({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 64,
          child: Row(children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: InkWell(
                  onTap: () => onTap(i),
                  child: Stack(alignment: Alignment.center, children: [
                    if (i == index)
                      Positioned(
                        top: 0,
                        child: Container(
                          width: 32,
                          height: 3,
                          decoration: const BoxDecoration(
                            color: AppColors.gold,
                            borderRadius: BorderRadius.vertical(bottom: Radius.circular(3)),
                          ),
                        ),
                      ),
                    Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Badge(
                        isLabelVisible: items[i].badge > 0,
                        label: Text('${items[i].badge}'),
                        child: Icon(items[i].icon,
                            size: 24, color: i == index ? AppColors.primary : AppColors.textSecondary),
                      ),
                      const SizedBox(height: 3),
                      Text(items[i].label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                            color: i == index ? AppColors.primary : AppColors.textSecondary,
                          )),
                    ]),
                  ]),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Status label in the booking colours from the design.
class StatusPill extends StatelessWidget {
  final String status;
  final String? label;
  const StatusPill(this.status, {super.key, this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: StatusColors.background(status), borderRadius: AppRadius.xsAll),
      child: Text(label ?? StatusColors.label(status),
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: StatusColors.foreground(status))),
    );
  }
}

/// Dark forest header block used at the top of key screens.
class ForestHeader extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const ForestHeader({super.key, required this.child, this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 20)});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primary,
      child: SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
    );
  }
}
