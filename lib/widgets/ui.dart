import 'package:flutter/material.dart';
import '../theme.dart';

/// Rounded mulberry square with a "B" and a honey dot — the app mark.
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
        borderRadius: BorderRadius.circular(size * 0.3),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: size * 0.4,
            offset: Offset(0, size * 0.12),
          ),
        ],
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
      color: color.withValues(alpha: 0.08),
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), shape: BoxShape.circle),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: const TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                ],
              ]),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(actionLabel!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: color)),
            ] else if (onTap != null)
              Icon(Icons.chevron_right_rounded, color: color),
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
        color: solid ? color : color.withValues(alpha: 0.1),
        borderRadius: AppRadius.pill,
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13, color: fg), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
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
      return const Pill(label: 'New', color: AppColors.info, icon: Icons.auto_awesome_rounded);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 16, color: AppColors.secondary),
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
    final initial = name.trim().isNotEmpty ? name.trim()[0].toUpperCase() : '?';
    final fallback = Center(
      child: Text(initial,
          style: TextStyle(fontSize: size * 0.4, fontWeight: FontWeight.w800, color: AppColors.primary)),
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
            width: 88,
            height: 88,
            decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
            child: Icon(icon, size: 38, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(title, style: Theme.of(context).textTheme.titleLarge, textAlign: TextAlign.center),
          const SizedBox(height: AppSpacing.sm),
          Text(message, style: Theme.of(context).textTheme.bodyMedium, textAlign: TextAlign.center),
          if (actionLabel != null) ...[
            const SizedBox(height: AppSpacing.xxl),
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
}

/// Built-in icon for a service category (avoids downloading an emoji font on web).
IconData categoryIcon(String? name) {
  final n = (name ?? '').toLowerCase();
  if (n.contains('barber')) return Icons.content_cut_rounded;
  if (n.contains('braid') || n.contains('locs') || n.contains('weave') || n.contains('wig')) {
    return Icons.face_retouching_natural_rounded;
  }
  if (n.contains('natural') || n.contains('relaxed') || n.contains('hair')) return Icons.spa_rounded;
  if (n.contains('kid')) return Icons.child_care_rounded;
  if (n.contains('bridal')) return Icons.favorite_rounded;
  if (n.contains('colour') || n.contains('color')) return Icons.palette_rounded;
  if (n.contains('lash') || n.contains('brow')) return Icons.visibility_rounded;
  if (n.contains('makeup')) return Icons.brush_rounded;
  if (n.contains('massage')) return Icons.self_improvement_rounded;
  if (n.contains('nail')) return Icons.back_hand_rounded;
  if (n.contains('skin')) return Icons.water_drop_rounded;
  if (n.contains('tattoo') || n.contains('pierc')) return Icons.draw_rounded;
  return Icons.auto_awesome_rounded;
}

class CategoryBadge extends StatelessWidget {
  final String? name;
  final double size;
  const CategoryBadge({super.key, required this.name, this.size = 44});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(size * 0.3)),
      child: Icon(categoryIcon(name), size: size * 0.5, color: AppColors.primary),
    );
  }
}
