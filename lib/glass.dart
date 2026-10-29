import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'theme.dart';

/// iOS 26 surfaces for BeauTap. Like iOS, content sits on plain system
/// backgrounds in flat rounded cells; Liquid Glass (real blur, a bright rim)
/// is only used for the things that float above content: the tab bar,
/// navigation bars and floating buttons.
class Glass {
  static bool get _d => AppColors.isDark;
  static Color _w(double a) => Colors.white.withValues(alpha: a);

  /// Big cards: a diagonal sheen.
  static Gradient get panel => _d
      ? LinearGradient(
          begin: const Alignment(-0.5, -1),
          end: const Alignment(0.5, 1),
          colors: [_w(0.15), _w(0.045), _w(0.08)],
          stops: const [0, 0.48, 1],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_w(0.86), _w(0.6), _w(0.7)],
          stops: const [0, 0.5, 1],
        );

  /// Small cards, list items, stat tiles.
  static Gradient get tile => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: _d ? [_w(0.11), _w(0.035)] : [_w(0.84), _w(0.62)],
      );

  /// Light catching the top edge.
  static Gradient get rim => _d
      ? LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [_w(0.5), _w(0.16), _w(0.15), _w(0.07)],
          stops: const [0, 0.1, 0.5, 1],
        )
      : LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, _w(0.55), _w(0.9)],
          stops: const [0, 0.5, 1],
        );

  /// iOS cards cast almost no shadow.
  static List<BoxShadow> get shadow => const [];

  /// Liquid Glass for bars: a light, see-through pane over blurred content.
  static Color get bar => _d ? const Color(0xA824211D) : const Color(0x9EFBF8F2);

  /// Sheets and dialogs (systemBackground / elevated).
  static Color get modal => _d ? const Color(0xFF191714) : Colors.white;

  /// The main (prominent) button: solid tint, like iOS.
  static Gradient get cta => LinearGradient(colors: [AppColors.primary, AppColors.primary]);

  static List<BoxShadow> get ctaGlow => const [];

  /// Deep green hero card (balances, next booking, plans).
  static BoxDecoration hero([double radius = 28]) => BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: const Color(0x2EFFFFFF)),
        boxShadow: const [BoxShadow(color: Color(0x520F3B31), blurRadius: 34, offset: Offset(0, 14))],
      );

  /// Gold accent button (the round "+" style).
  static const goldGradient = LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFE9CF96), Color(0xFFC8A15A)]);
  static List<BoxShadow> get goldGlow =>
      const [BoxShadow(color: Color(0x8CC8A15A), blurRadius: 22, offset: Offset(0, 8))];

  /// Blur that also boosts colour behind the pane, like iOS 26 glass.
  static ImageFilter frost([double sigma = 26]) {
    const s = 1.8, b = 1.04;
    const r = (1 - s) * 0.2126, g = (1 - s) * 0.7152, bl = (1 - s) * 0.0722;
    return ImageFilter.compose(
      outer: const ColorFilter.matrix(<double>[
        (r + s) * b, g * b, bl * b, 0, 0, //
        r * b, (g + s) * b, bl * b, 0, 0,
        r * b, g * b, (bl + s) * b, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      inner: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }
}

/// A 1.1 px gradient outline: the bright edge of liquid glass.
class RimDecoration extends Decoration {
  final double radius;
  final Gradient gradient;
  const RimDecoration({required this.radius, required this.gradient});

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) => _RimPainter(radius, gradient);
}

class _RimPainter extends BoxPainter {
  final double radius;
  final Gradient gradient;
  _RimPainter(this.radius, this.gradient);

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration config) {
    final size = config.size;
    if (size == null) return;
    final rect = (offset & size).deflate(0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(radius)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..shader = gradient.createShader(rect),
    );
  }
}

/// An iOS card: a flat rounded cell on the grey page (grouped style).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final VoidCallback? onTap;
  final bool tile;
  final EdgeInsetsGeometry? margin;
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.onTap,
    this.tile = false,
    this.margin,
  });

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    final card = Material(
      color: tile ? AppColors.surfaceMuted : AppColors.card,
      borderRadius: r,
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
    return margin == null ? card : Padding(padding: margin!, child: card);
  }
}

/// Frosted glass with real blur, for bars and floating pieces only.
class GlassBar extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry? padding;

  /// Real blur. Turn it off when nothing scrolls behind the bar.
  final bool blur;
  const GlassBar({super.key, required this.child, this.radius = 32, this.padding, this.blur = true});

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: r, boxShadow: [
        BoxShadow(color: Colors.black.withValues(alpha: AppColors.isDark ? 0.35 : 0.12), blurRadius: 30, offset: const Offset(0, 12)),
      ]),
      child: ClipRRect(
        borderRadius: r,
        child: blur ? BackdropFilter(filter: Glass.frost(), child: _pane(r)) : _pane(r),
      ),
    );
  }
}

extension on GlassBar {
  Widget _pane(BorderRadius r) => DecoratedBox(
        decoration: BoxDecoration(color: Glass.bar, gradient: AppColors.isDark ? Glass.panel : null, borderRadius: r),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: RimDecoration(radius: radius, gradient: Glass.rim),
          child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
        ),
      );
}

/// The glowing main action ("Book a time", "Confirm").
class GlowButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;
  const GlowButton({super.key, required this.label, this.icon, this.onPressed, this.expand = true});

  @override
  Widget build(BuildContext context) {
    final on = onPressed != null;
    final fg = AppColors.onPrimary;
    return Opacity(
      opacity: on ? 1 : 0.5,
      child: DecoratedBox(
        decoration: BoxDecoration(gradient: Glass.cta, borderRadius: BorderRadius.circular(28), boxShadow: on ? Glass.ctaGlow : null),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: onPressed,
            child: SizedBox(
              height: 50,
              width: expand ? double.infinity : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: -0.3, color: fg)),
                  if (icon != null) ...[const SizedBox(width: 8), Icon(icon, color: fg, size: 20)],
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The page background: iOS's systemGroupedBackground (light grey, or black
/// in dark mode). Every page gets it, so pages are never see-through.
class MeshBackground extends StatelessWidget {
  final Widget child;
  const MeshBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) => ColoredBox(color: AppColors.surfaceLight, child: child);
}

/// iPhone-style page slide (also on Android, with swipe-back from the edge),
/// and every page gets the glow background so it's never see-through.
class GlassPageTransitions extends PageTransitionsBuilder {
  const GlassPageTransitions();
  static const _slide = CupertinoPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    return _slide.buildTransitions(route, context, animation, secondaryAnimation, MeshBackground(child: child));
  }
}
