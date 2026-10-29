import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../glass.dart';
import '../theme.dart';
import '../utils/feel.dart';

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
        color: const Color(0xFF141210),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Stack(children: [
        Center(
          child: Text(
            'B',
            style: TextStyle(
              color: AppColors.gold,
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
            decoration: const BoxDecoration(color: Color(0xFFF7F3EC), shape: BoxShape.circle),
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
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                if (message != null) ...[
                  const SizedBox(height: 2),
                  Text(message!, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
                ],
              ]),
            ),
            if (actionLabel != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Text(actionLabel!, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
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
  final Color? _color;
  final IconData? icon;
  final bool solid;
  const Pill({super.key, required this.label, Color? color, this.icon, this.solid = false}) : _color = color;

  Color get color => _color ?? AppColors.primary;

  @override
  Widget build(BuildContext context) {
    final fg = solid ? AppColors.onPrimary : color;
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
      return Pill(label: 'New', color: AppColors.primary, solid: true);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(TablerIcons.star_filled, size: 16, color: Color(0xFFA8822F)),
      const SizedBox(width: 3),
      Text(rating.toStringAsFixed(1),
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      Text(' ($reviews)', style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
    ]);
  }
}

/// Circle with a photo, or the person's initial on a blush background.
/// A pro's photo for cards: their work photo, else their profile photo, else
/// a soft pastel tile with their initials, so a pro without photos never
/// looks empty. The pastel is picked from the name, so it stays the same.
class ProPhoto extends StatelessWidget {
  final String name;
  final String? url;
  final double radius;
  final bool showNoPhotoNote;
  const ProPhoto({super.key, required this.name, this.url, this.radius = 18, this.showNoPhotoNote = false});

  static const _light = [
    [Color(0xFFF6E3C8), Color(0xFFEBC9A0)], // sand
    [Color(0xFFF7DCD3), Color(0xFFEDBCAB)], // peach
    [Color(0xFFE3E8D5), Color(0xFFC9D3B0)], // sage
    [Color(0xFFDDE6EE), Color(0xFFBFD0DE)], // sky
  ];
  static const _dark = [
    [Color(0xFF3A2E1E), Color(0xFF221B12)],
    [Color(0xFF3B261F), Color(0xFF231612)],
    [Color(0xFF2C3122), Color(0xFF1A1E14)],
    [Color(0xFF23303A), Color(0xFF141C22)],
  ];

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    return (parts.first[0] + (parts.length > 1 ? parts.last[0] : '')).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final pick = name.codeUnits.fold<int>(0, (a, b) => a + b) % _light.length;
    final colors = (AppColors.isDark ? _dark : _light)[pick];
    final ink = AppColors.isDark ? const Color(0xFFE2BE7A) : const Color(0xFF6B4E22);
    final fallback = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: colors),
      ),
      child: LayoutBuilder(builder: (context, c) {
        return Stack(fit: StackFit.expand, children: [
          Center(
            child: Text(initials(name),
                style: TextStyle(
                    fontFamily: 'InterDisplay',
                    fontSize: (c.maxWidth * 0.32).clamp(16, 56),
                    fontWeight: FontWeight.w700,
                    color: ink)),
          ),
          if (showNoPhotoNote && c.maxHeight > 80)
            Positioned(
              left: 4,
              right: 4,
              bottom: 6,
              child: Text('No photo yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: ink.withValues(alpha: 0.8))),
            ),
        ]);
      }),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: (url != null && url!.isNotEmpty)
          ? Image.network(url!,
              fit: BoxFit.cover,
              alignment: const Alignment(0, -0.4),
              cacheWidth: 600,
              errorBuilder: (_, __, ___) => fallback,
              frameBuilder: (_, child, frame, sync) => sync
                  ? child
                  : AnimatedOpacity(opacity: frame == null ? 0 : 1, duration: const Duration(milliseconds: 260), child: child))
          : fallback,
    );
  }
}

/// Small dark-glass label printed on a photo: "★ 4.9", "2.1 km", "New".
class PhotoBadge extends StatelessWidget {
  final String text;
  final bool gold;
  const PhotoBadge({super.key, required this.text, this.gold = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 26,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: gold ? AppColors.gold : const Color(0xA6141210),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(text,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: gold ? const Color(0xFF17130E) : Colors.white)),
    );
  }
}

/// Heart on a photo. Pops when tapped; filled red when saved.
class HeartButton extends StatefulWidget {
  final bool saved;
  final VoidCallback onTap;
  final double size;
  const HeartButton({super.key, required this.saved, required this.onTap, this.size = 32});

  @override
  State<HeartButton> createState() => _HeartButtonState();
}

class _HeartButtonState extends State<HeartButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 320));

  @override
  void didUpdateWidget(HeartButton old) {
    super.didUpdateWidget(old);
    if (widget.saved && !old.saved && !Motion.reduced(context)) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      toggled: widget.saved,
      label: widget.saved ? 'Remove from saved' : 'Save',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ScaleTransition(
          scale: TweenSequence<double>([
            TweenSequenceItem(tween: Tween(begin: 1, end: 1.3), weight: 40),
            TweenSequenceItem(tween: Tween(begin: 1.3, end: 1), weight: 60),
          ]).animate(CurvedAnimation(parent: _pop, curve: Curves.easeOut)),
          child: Container(
            width: widget.size,
            height: widget.size,
            decoration: const BoxDecoration(color: Color(0xEBFFFFFF), shape: BoxShape.circle),
            child: Icon(widget.saved ? TablerIcons.heart_filled : TablerIcons.heart,
                size: widget.size * 0.55, color: widget.saved ? const Color(0xFFE5484D) : const Color(0xFF17130E)),
          ),
        ),
      ),
    );
  }
}

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
      decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
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
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
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
  /// Bundled stock photo for chips and tiles (assets/photos, see CREDITS.md).
  final String photo;
  const ServiceGroup(this.name, this.icon, this.keywords, this.photo);

  bool matches(String? categoryName) {
    final n = (categoryName ?? '').toLowerCase();
    return keywords.any(n.contains);
  }

  static const all = [
    ServiceGroup('Hair', TablerIcons.ripple, ['braid', 'wig', 'natural', 'kid', 'loc', 'relax', 'weave', 'colour', 'color', 'hair', 'cuts & styling'], 'assets/photos/cat_hair.jpg'),
    ServiceGroup('Barbering', TablerIcons.scissors, ['barber', 'fade', 'beard', 'shave', 'groom'], 'assets/photos/cat_barbering.jpg'),
    ServiceGroup('Nails', TablerIcons.hand_finger, ['nail', 'manicure', 'pedicure', 'gel', 'acrylic'], 'assets/photos/cat_nails.jpg'),
    ServiceGroup('Lashes & Brows', TablerIcons.eye, ['lash', 'brow', 'microblad'], 'assets/photos/cat_lashes.jpg'),
    ServiceGroup('Makeup', TablerIcons.brush, ['makeup', 'make-up'], 'assets/photos/cat_makeup.jpg'),
    ServiceGroup('Skin', TablerIcons.droplet, ['skin', 'facial', 'peel'], 'assets/photos/cat_skin.jpg'),
    ServiceGroup('Hair Removal', TablerIcons.feather, ['wax', 'thread', 'sugar', 'removal'], 'assets/photos/cat_hair_removal.jpg'),
    ServiceGroup('Body & Spa', TablerIcons.leaf, ['massage', 'spa', 'scrub', 'wrap', 'reflex'], 'assets/photos/cat_spa.jpg'),
    ServiceGroup('Glow', TablerIcons.sun_high, ['spray tan', 'whiten', 'glow'], 'assets/photos/cat_glow.jpg'),
    ServiceGroup('Body Art', TablerIcons.palette, ['tattoo', 'pierc', 'henna'], 'assets/photos/cat_body_art.jpg'),
    ServiceGroup('Bridal & Events', TablerIcons.diamond, ['bridal', 'event', 'wedding', 'photoshoot'], 'assets/photos/cat_bridal.jpg'),
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
/// iOS grouped section (Settings style): an optional small grey header,
/// rows in one rounded white card with hairline dividers, optional footer.
class IosSection extends StatelessWidget {
  final String? header;
  final String? footer;
  final List<Widget> children;
  const IosSection({super.key, this.header, this.footer, required this.children});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) rows.add(Padding(padding: const EdgeInsets.only(left: 58), child: Divider(height: 0.5, color: AppColors.border)));
      rows.add(children[i]);
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 7),
            child: Text(header!.toUpperCase(),
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w400, letterSpacing: 0.1, color: AppColors.textSecondary)),
          ),
        Material(
          color: AppColors.card,
          borderRadius: AppRadius.lgAll,
          clipBehavior: Clip.antiAlias,
          child: Column(children: rows),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
            child: Text(footer!, style: TextStyle(fontSize: 13, height: 1.35, color: AppColors.textSecondary)),
          ),
      ]),
    );
  }
}

/// One iOS Settings row: coloured icon square, title, optional subtitle,
/// optional value on the right, and a grey chevron.
class IosRow extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;
  final String title;
  final String? subtitle;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool destructive;
  const IosRow({
    super.key,
    this.icon,
    this.iconColor,
    required this.title,
    this.subtitle,
    this.value,
    this.trailing,
    this.onTap,
    this.destructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final titleColor = destructive ? AppColors.error : AppColors.textPrimary;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 50),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
          child: Row(children: [
            if (icon != null) ...[
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(color: iconColor ?? AppColors.forest, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(title, style: TextStyle(fontSize: 17, letterSpacing: -0.3, color: titleColor)),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(subtitle!, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ),
              ]),
            ),
            if (value != null) ...[
              const SizedBox(width: 8),
              Text(value!, style: TextStyle(fontSize: 17, letterSpacing: -0.3, color: AppColors.textSecondary)),
            ],
            if (trailing != null) ...[const SizedBox(width: 8), trailing!]
            else if (onTap != null && !destructive) ...[
              const SizedBox(width: 6),
              Icon(Icons.chevron_right_rounded, size: 24, color: AppColors.textTertiary.withValues(alpha: 0.7)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// iOS Settings icon colours.
class IosColors {
  static const red = Color(0xFFFF3B30);
  static const orange = Color(0xFFFF9500);
  static const yellow = Color(0xFFFFCC00);
  static const green = Color(0xFF34C759);
  static const teal = Color(0xFF30B0C7);
  static const blue = Color(0xFF007AFF);
  static const indigo = Color(0xFF5856D6);
  static const purple = Color(0xFFAF52DE);
  static const pink = Color(0xFFFF2D55);
  static const gray = Color(0xFF8E8E93);
  static const forest = Color(0xFF0F3B31);
  static const gold = Color(0xFFC8A15A);
}

/// iOS large-title navigation bar for tab pages: the bar itself stays
/// empty (actions on the right) and the 34pt bold title sits under it, on
/// the left, like Mail, Settings and Photos.
AppBar largeTitleBar(BuildContext context, String title, {List<Widget>? actions, PreferredSizeWidget? bottom}) {
  final bottomH = bottom?.preferredSize.height ?? 0;
  return AppBar(
    automaticallyImplyLeading: false,
    toolbarHeight: 44,
    actions: actions,
    bottom: PreferredSize(
      preferredSize: Size.fromHeight(50 + bottomH),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Same width and centring as PageWidth, so the title lines up with the content.
        PageWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.displaySmall),
            ),
          ),
        ),
        ?bottom,
      ]),
    ),
  );
}

/// A tab page's floating button, lifted above the floating glass tab bar on
/// phones (the page runs under the bar, so it would otherwise hide there).
Widget tabFab(BuildContext context, Widget fab) => isWideLayout(context)
    ? fab
    : Padding(padding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom), child: fab);

/// Room to leave at the end of a tab page's list so the last item can
/// scroll clear of the floating tab bar (content runs under the glass).
double tabBarSpace(BuildContext context) => MediaQuery.paddingOf(context).bottom + 12;

/// BeauTap 2.0 tab bar: a floating black capsule. The open tab grows into a
/// gold pill with its label; the others are icons. A light haptic tick on
/// every switch.
class BeauNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<({IconData icon, String label, int badge})> items;
  const BeauNavBar({super.key, required this.index, required this.onTap, required this.items});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: dark ? Colors.black : const Color(0xFF141210),
            borderRadius: BorderRadius.circular(40),
            border: dark ? Border.all(color: const Color(0xFF2A2722)) : null,
            boxShadow: const [BoxShadow(color: Color(0x47000000), blurRadius: 30, offset: Offset(0, 12))],
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < items.length; i++)
              _NavItem(
                item: items[i],
                selected: i == index,
                onTap: () {
                  if (i != index) Haptics.light();
                  onTap(i);
                },
              ),
          ]),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final ({IconData icon, String label, int badge}) item;
  final bool selected;
  final VoidCallback onTap;
  const _NavItem({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17130E);
    final icon = Badge(
      isLabelVisible: item.badge > 0,
      label: Text('${item.badge}'),
      child: Icon(item.icon, size: 23, color: selected ? ink : const Color(0xFFCFC6B8)),
    );
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.of(context),
          curve: Motion.curve,
          height: 48,
          constraints: const BoxConstraints(minWidth: 52),
          padding: EdgeInsets.symmetric(horizontal: selected ? 16 : 12),
          decoration: BoxDecoration(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(28),
          ),
          child: AnimatedSize(
            duration: Motion.of(context),
            curve: Motion.curve,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              icon,
              if (selected) ...[
                const SizedBox(width: 8),
                Text(item.label,
                    maxLines: 1,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: ink)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// From this width up (laptops, iPad landscape) the app uses the iPadOS
/// layout: a sidebar instead of the bottom tab bar, and pages fill the screen.
const double kWideBreakpoint = 1000;
bool isWideLayout(BuildContext context) => MediaQuery.sizeOf(context).width >= kWideBreakpoint;

typedef TabItem = ({IconData icon, String label, int badge});

/// The tab scaffold for both shells: the floating glass tab bar on phones,
/// an iPadOS 26 glass sidebar on wide screens.
class AdaptiveTabScaffold extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<TabItem> items;
  final Widget body;
  final String subtitle;
  const AdaptiveTabScaffold({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
    required this.body,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) {
      return Scaffold(
        // Content runs under the floating glass tab bar, like iOS 26.
        extendBody: true,
        body: body,
        bottomNavigationBar: BeauNavBar(index: index, onTap: onTap, items: items),
      );
    }
    return Scaffold(
      body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        BeauSidebar(index: index, onTap: onTap, items: items, subtitle: subtitle),
        Expanded(child: body),
      ]),
    );
  }
}

/// iPadOS 26 sidebar: a floating Liquid Glass panel down the left edge.
class BeauSidebar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<TabItem> items;
  final String subtitle;
  const BeauSidebar({super.key, required this.index, required this.onTap, required this.items, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      right: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 0, 12),
        child: SizedBox(
          width: 248,
          child: GlassBar(
            radius: 28,
            padding: const EdgeInsets.fromLTRB(10, 18, 10, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 20),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(9),
                    child: Image.asset('assets/branding/app_mark.png', width: 34, height: 34, cacheWidth: 102),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('BeauTap', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                      Text(subtitle, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    ]),
                  ),
                ]),
              ),
              for (var i = 0; i < items.length; i++)
                _SidebarItem(item: items[i], selected: i == index, onTap: () => onTap(i)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  final TabItem item;
  final bool selected;
  final VoidCallback onTap;
  const _SidebarItem({required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF17130E) : AppColors.textPrimary;
    return Semantics(
      selected: selected,
      button: true,
      label: item.label,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Material(
          color: selected ? AppColors.gold : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                const SizedBox(width: 12),
                Icon(item.icon, size: 22, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(item.label,
                      style: TextStyle(fontSize: 16, fontWeight: selected ? FontWeight.w600 : FontWeight.w500, color: color)),
                ),
                if (item.badge > 0) ...[
                  Badge(label: Text('${item.badge}')),
                  const SizedBox(width: 12),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Widest a page's content gets on big monitors, so rows stay readable.
const double kPageMaxWidth = 1240;

/// Lays [children] (usually [IosSection]s) out in as many columns as fit,
/// keeping their order: left to right, then down. One column on phones.
class AdaptiveColumns extends StatelessWidget {
  final List<Widget> children;
  final double minColumnWidth;
  final int maxColumns;
  final double gap;
  const AdaptiveColumns({super.key, required this.children, this.minColumnWidth = 380, this.maxColumns = 2, this.gap = 20});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = ((c.maxWidth + gap) / (minColumnWidth + gap)).floor().clamp(1, maxColumns);
      if (cols == 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      }
      final columns = List.generate(cols, (_) => <Widget>[]);
      for (var i = 0; i < children.length; i++) {
        columns[i % cols].add(children[i]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var i = 0; i < cols; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: columns[i])),
        ],
      ]);
    });
  }
}

/// Cards in a grid that fills the width: one per row on phones, two or
/// three side by side on wide screens. Cards keep their own height.
class AdaptiveGrid extends StatelessWidget {
  final List<Widget> children;
  final double minTileWidth;
  final double gap;
  const AdaptiveGrid({super.key, required this.children, this.minTileWidth = 360, this.gap = 12});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = ((c.maxWidth + gap) / (minTileWidth + gap)).floor().clamp(1, 4);
      if (cols == 1) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        for (var r = 0; r < children.length; r += cols)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = r; i < r + cols; i++) ...[
              if (i > r) SizedBox(width: gap),
              Expanded(child: i < children.length ? children[i] : const SizedBox()),
            ],
          ]),
      ]);
    });
  }
}

/// Widest a detail or form page gets on wide screens.
const double kReadableMaxWidth = 880;

/// Detail and form pages (everything outside the tab shells) on wide
/// screens: one centred, readable column, like an iPad detail page. The
/// router applies this to every such page; phones are unaffected.
class ReadablePage extends StatelessWidget {
  final Widget child;
  const ReadablePage({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!isWideLayout(context)) return child;
    return Center(
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: kReadableMaxWidth), child: child),
    );
  }
}

/// Centres a tab page's content and stops it growing past [kPageMaxWidth].
class PageWidth extends StatelessWidget {
  final Widget child;
  final double maxWidth;
  const PageWidth({super.key, required this.child, this.maxWidth = kPageMaxWidth});

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
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
    // Deep green glass with a gold glow, rounded at the bottom.
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(28)),
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: AppColors.heroGradient),
        child: Stack(children: [
          Positioned(
            right: -80,
            top: -90,
            child: Container(
              width: 240,
              height: 240,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [Color(0x73C8A15A), Color(0x00C8A15A)]),
              ),
            ),
          ),
          SafeArea(bottom: false, child: Padding(padding: padding, child: child)),
        ]),
      ),
    );
  }
}

/// Wrap bottom-sheet content so it never grows past 90% of the screen and
/// scrolls when it's taller (small phones, long lists, keyboard open).
class SheetScroll extends StatelessWidget {
  final Widget child;
  const SheetScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: SingleChildScrollView(child: child),
      );
}

enum PlaceholderKind { list, detail, profile }

/// Grey shapes that pulse while a screen loads, laid out like the content
/// that's coming, so the page doesn't jump when it arrives.
class LoadingPlaceholder extends StatefulWidget {
  final PlaceholderKind kind;
  const LoadingPlaceholder({super.key, this.kind = PlaceholderKind.list});

  @override
  State<LoadingPlaceholder> createState() => _LoadingPlaceholderState();
}

class _LoadingPlaceholderState extends State<LoadingPlaceholder> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _box({double? w, double h = 14, double r = 6}) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(r)),
      );

  Widget _card({bool avatar = true}) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          if (avatar) ...[_box(w: 44, h: 44, r: 22), const SizedBox(width: 12)],
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _box(w: 160, h: 14),
              const SizedBox(height: 8),
              _box(w: 110, h: 12),
            ]),
          ),
          _box(w: 44, h: 16),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = switch (widget.kind) {
      PlaceholderKind.list => [for (var i = 0; i < 6; i++) _card()],
      PlaceholderKind.detail => [
          _box(h: 120, r: 20),
          const SizedBox(height: 16),
          _box(w: 180, h: 18),
          const SizedBox(height: 10),
          _box(h: 12),
          const SizedBox(height: 6),
          _box(w: 240, h: 12),
          const SizedBox(height: 20),
          _card(avatar: false),
          _card(avatar: false),
          _card(avatar: false),
        ],
      PlaceholderKind.profile => [
          Row(children: [
            _box(w: 72, h: 72, r: 36),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _box(w: 160, h: 20),
                const SizedBox(height: 8),
                _box(w: 120, h: 12),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          Row(children: [Expanded(child: _box(h: 60, r: 12)), const SizedBox(width: 10), Expanded(child: _box(h: 60, r: 12))]),
          const SizedBox(height: 20),
          _box(w: 100, h: 16),
          const SizedBox(height: 10),
          _card(avatar: false),
          _card(avatar: false),
        ],
    };
    return SafeArea(
      child: FadeTransition(
        opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
        child: ListView(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: children,
        ),
      ),
    );
  }
}
