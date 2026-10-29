import 'dart:ui';

import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'theme.dart';

/// BeauTap liquid glass (after the Command Center and Electrical apps), in
/// forest and gold. Layers, each more solid: panel > tile > control > modal.
/// Real blur is only used on bars and floating pieces; cards fake the glass
/// with gradients so cheaper phones stay smooth.
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

  static List<BoxShadow> get shadow => _d
      ? const [BoxShadow(color: Color(0x73000A06), blurRadius: 40, offset: Offset(0, 16))]
      : const [
          BoxShadow(color: Color(0x1A0F3B31), blurRadius: 30, offset: Offset(0, 12)),
          BoxShadow(color: Color(0x0D0F3B31), blurRadius: 6, offset: Offset(0, 2)),
        ];

  /// Floating bars (tab bar, book bar): the most solid glass that still glows.
  static Color get bar => _d ? const Color(0xDB10221C) : _w(0.86);

  /// Sheets and dialogs.
  static Color get modal => _d ? const Color(0xF2122B23) : const Color(0xF7FBFCFA);

  /// The glowing main button.
  static Gradient get cta => _d
      ? const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFA6E3CB), Color(0xFF5FB394)])
      : const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF22604F), Color(0xFF0F3B31)]);

  static List<BoxShadow> get ctaGlow => [
        BoxShadow(
          color: (_d ? const Color(0xFF7CC7AB) : const Color(0xFF0F3B31)).withValues(alpha: _d ? 0.38 : 0.32),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ];

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

/// Glass card without real blur (cheap): sheen, rim and a soft shadow.
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
    final card = DecoratedBox(
      decoration: BoxDecoration(gradient: tile ? Glass.tile : Glass.panel, borderRadius: r, boxShadow: tile ? null : Glass.shadow),
      child: DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: RimDecoration(radius: radius, gradient: Glass.rim),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(borderRadius: r, onTap: onTap, child: Padding(padding: padding, child: child)),
        ),
      ),
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
    final fg = AppColors.isDark ? const Color(0xFF0B2C25) : Colors.white;
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
              height: 54,
              width: expand ? double.infinity : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(mainAxisSize: MainAxisSize.min, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: TextStyle(fontFamily: AppTheme.fontFamily, fontSize: 16, fontWeight: FontWeight.w800, color: fg)),
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

/// The soft, still glow behind every page: mint and gold on cream in light
/// mode, deep forest with mint and gold in dark mode. Static on purpose, so
/// it costs nothing once drawn.
class MeshBackground extends StatelessWidget {
  final Widget child;
  const MeshBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark ? const [Color(0xFF10231D), Color(0xFF08120F)] : const [Color(0xFFF6F8F4), Color(0xFFEDF1EB)],
        ),
      ),
      child: Stack(fit: StackFit.expand, children: [
        RepaintBoundary(child: CustomPaint(painter: _MeshPainter(dark))),
        child,
      ]),
    );
  }
}

class _MeshPainter extends CustomPainter {
  final bool dark;
  _MeshPainter(this.dark);

  @override
  void paint(Canvas canvas, Size size) {
    final v = size.longestSide;
    void glow(Offset at, double radius, Color c) {
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..shader = RadialGradient(colors: [c, c.withValues(alpha: 0)], stops: const [0, 0.62])
              .createShader(Rect.fromCircle(center: at, radius: radius)),
      );
    }

    if (dark) {
      glow(Offset(size.width * -0.05, size.height * 0.02), v * 0.7, const Color(0xA62A6E5A));
      glow(Offset(size.width * 1.05, size.height * 0.2), v * 0.55, const Color(0x38C8A15A));
      glow(Offset(size.width * 0.5, size.height * 1.05), v * 0.65, const Color(0x337CC7AB));
    } else {
      glow(Offset(size.width * -0.08, size.height * 0.03), v * 0.65, const Color(0x8C7CC7AB));
      glow(Offset(size.width * 1.08, size.height * 0.18), v * 0.55, const Color(0xB3E7D3A6));
      glow(Offset(size.width * 0.5, size.height * 1.08), v * 0.65, const Color(0x1F0F3B31));
    }
  }

  @override
  bool shouldRepaint(_MeshPainter old) => old.dark != dark;
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
