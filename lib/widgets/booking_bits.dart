import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../theme.dart';
import '../utils/feel.dart';

/// Service → Time → Pay → Done. Finished steps are gold with a tick and can
/// be tapped to go back.
class BookingStepBar extends StatelessWidget {
  final int step;
  final List<String> titles;
  final ValueChanged<int>? onTapStep;
  const BookingStepBar({super.key, required this.step, required this.titles, this.onTapStep});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      for (var i = 0; i < titles.length; i++) ...[
        Expanded(
          child: Semantics(
            button: i < step,
            label: '${titles[i]}${i < step ? ', done' : i == step ? ', current step' : ''}',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: i < step && onTapStep != null ? () => onTapStep!(i) : null,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                AnimatedContainer(
                  duration: Motion.of(context),
                  curve: Motion.curve,
                  height: 4,
                  decoration: BoxDecoration(
                    color: i <= step ? AppColors.gold : AppColors.border,
                    borderRadius: AppRadius.pill,
                  ),
                ),
                const SizedBox(height: 6),
                Text(i < step ? '${titles[i]} ✓' : titles[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: i == step ? FontWeight.w700 : FontWeight.w600,
                        color: i == step
                            ? AppColors.textPrimary
                            : i < step
                                ? AppColors.goldText
                                : AppColors.textSecondary)),
              ]),
            ),
          ),
        ),
        if (i < titles.length - 1) const SizedBox(width: 6),
      ],
    ]);
  }
}

/// The big ink button at the bottom: "$40 · Continue".
class BigPriceButton extends StatelessWidget {
  final String price;
  final String label;
  final bool busy;
  final VoidCallback? onPressed;
  const BigPriceButton({super.key, required this.price, required this.label, this.busy = false, this.onPressed});

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.onPrimary;
    return SizedBox(
      height: 58,
      width: double.infinity,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: fg,
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600),
        ),
        child: busy
            ? SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2.4, valueColor: AlwaysStoppedAnimation(fg)))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Text(price),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Text('·', style: TextStyle(color: fg.withValues(alpha: 0.55))),
                ),
                Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
              ]),
      ),
    );
  }
}

/// "Slide to book ›››". Light ticks while dragging, a firm buzz at the end,
/// springs back if let go early. Screen readers get a plain button.
class SlideToBook extends StatefulWidget {
  final String label;
  final bool busy;
  final VoidCallback? onConfirm;
  const SlideToBook({super.key, this.label = 'Slide to book', this.busy = false, this.onConfirm});

  @override
  State<SlideToBook> createState() => _SlideToBookState();
}

class _SlideToBookState extends State<SlideToBook> with SingleTickerProviderStateMixin {
  static const _h = 62.0;
  static const _knob = 52.0;
  late final AnimationController _back = AnimationController(vsync: this, duration: Motion.normal)
    ..addListener(() => setState(() => _p = _from * (1 - Curves.easeOutBack.transform(_back.value).clamp(0, 1.1))));
  double _p = 0; // 0..1
  double _from = 0;
  int _lastTick = 0;
  bool _done = false;

  @override
  void didUpdateWidget(SlideToBook old) {
    super.didUpdateWidget(old);
    // Booking failed: let the client try again.
    if (old.busy && !widget.busy && _done) {
      _done = false;
      _release(force: true);
    }
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  void _release({bool force = false}) {
    if (_done && !force) return;
    _from = _p;
    if (Motion.reduced(context)) {
      setState(() => _p = 0);
    } else {
      _back.forward(from: 0);
    }
    _lastTick = 0;
  }

  void _confirm() {
    if (_done || widget.onConfirm == null) return;
    _done = true;
    _back.stop();
    setState(() => _p = 1);
    Haptics.firm();
    widget.onConfirm!();
  }

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final enabled = widget.onConfirm != null && !widget.busy;
    return LayoutBuilder(builder: (context, c) {
      final track = c.maxWidth - _knob - 10;
      final x = 5 + track * _p;
      return Semantics(
        button: true,
        enabled: enabled,
        label: '${widget.label}. Double tap to book.',
        excludeSemantics: true,
        onTap: enabled ? _confirm : null,
        child: GestureDetector(
          onHorizontalDragStart: enabled ? (_) => _back.stop() : null,
          onHorizontalDragUpdate: enabled
              ? (d) {
                  if (_done) return;
                  setState(() => _p = (_p + d.delta.dx / track).clamp(0.0, 1.0));
                  final tick = (_p * 4).floor();
                  if (tick > _lastTick) Haptics.light();
                  _lastTick = tick;
                  if (_p >= 0.98) _confirm();
                }
              : null,
          onHorizontalDragEnd: enabled ? (_) => _p >= 0.9 ? _confirm() : _release() : null,
          child: Container(
            height: _h,
            decoration: BoxDecoration(
              color: dark ? Colors.black : const Color(0xFF141210),
              borderRadius: BorderRadius.circular(_h / 2),
              border: dark ? Border.all(color: const Color(0xFF2F2A22)) : null,
            ),
            child: Stack(children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: x + _knob + 5,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_h / 2),
                    gradient: LinearGradient(colors: [
                      AppColors.gold.withValues(alpha: 0.06),
                      AppColors.gold.withValues(alpha: 0.45 * _p + 0.05),
                    ]),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: (1 - _p * 1.4).clamp(0.0, 1.0),
                  child: Padding(
                    padding: const EdgeInsets.only(left: _knob),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(widget.label,
                          style: const TextStyle(color: Color(0xFFE4DCCF), fontSize: 16, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 8),
                      Icon(TablerIcons.chevrons_right, color: AppColors.gold, size: 20),
                    ]),
                  ),
                ),
              ),
              Positioned(
                left: x,
                top: 5,
                child: Container(
                  width: _knob,
                  height: _knob,
                  decoration: BoxDecoration(
                    color: enabled || widget.busy ? AppColors.gold : AppColors.gold.withValues(alpha: 0.4),
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.45), blurRadius: 14, offset: const Offset(0, 4))],
                  ),
                  child: widget.busy
                      ? const Padding(
                          padding: EdgeInsets.all(15),
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF17130E)),
                        )
                      : Icon(_p >= 0.98 ? TablerIcons.check : TablerIcons.chevron_right,
                          color: const Color(0xFF17130E), size: 24),
                ),
              ),
            ]),
          ),
        ),
      );
    });
  }
}

/// Gold tick with a small burst of confetti, for "You're booked!".
class BookedCelebration extends StatefulWidget {
  final double size;
  const BookedCelebration({super.key, this.size = 150});

  @override
  State<BookedCelebration> createState() => _BookedCelebrationState();
}

class _BookedCelebrationState extends State<BookedCelebration> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c.status == AnimationStatus.dismissed) {
      Motion.reduced(context) ? _c.value = 1 : _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final pop = Curves.elasticOut.transform((_c.value / 0.7).clamp(0.0, 1.0));
        return SizedBox(
          width: s,
          height: s,
          child: CustomPaint(
            painter: _Confetti(_c.value, AppColors.gold, AppColors.textPrimary),
            child: Center(
              child: Transform.scale(
                scale: 0.4 + 0.6 * pop,
                child: Container(
                  width: s * 0.66,
                  height: s * 0.66,
                  decoration: BoxDecoration(
                    color: AppColors.gold,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.gold.withValues(alpha: 0.18), spreadRadius: 14),
                      BoxShadow(color: AppColors.gold.withValues(alpha: 0.07), spreadRadius: 30),
                    ],
                  ),
                  child: Icon(TablerIcons.check, size: s * 0.32, color: const Color(0xFF17130E)),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _Confetti extends CustomPainter {
  final double t;
  final Color a;
  final Color b;
  _Confetti(this.t, this.a, this.b);

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0.15) return;
    final p = Curves.easeOutCubic.transform(((t - 0.15) / 0.85).clamp(0.0, 1.0));
    final c = size.center(Offset.zero);
    final fade = t > 0.75 ? 1 - (t - 0.75) / 0.25 * 0.35 : 1.0;
    for (var i = 0; i < 12; i++) {
      final ang = i * math.pi * 2 / 12 + 0.3;
      final r = size.width * (0.34 + 0.2 * p) + (i.isEven ? 6 : -4);
      final o = c + Offset(math.cos(ang), math.sin(ang)) * r;
      final paint = Paint()..color = (i % 3 == 1 ? b : a).withValues(alpha: fade.toDouble());
      canvas.save();
      canvas.translate(o.dx, o.dy);
      canvas.rotate(ang + p * 2);
      if (i % 4 == 0) {
        canvas.drawCircle(Offset.zero, 3.2, paint);
      } else {
        canvas.drawRRect(RRect.fromRectAndRadius(const Rect.fromLTWH(-4, -4, 8, 8), const Radius.circular(2)), paint);
      }
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_Confetti old) => old.t != t;
}

/// Payment method colours, so EcoCash, InnBucks and OneMoney are easy to spot.
({Color bg, String mark}) payBrand(String id) => switch (id) {
      'ecocash' => (bg: const Color(0xFF0A63B6), mark: 'Eco'),
      'innbucks' => (bg: const Color(0xFFE23B3B), mark: 'Inn'),
      'onemoney' => (bg: const Color(0xFF1C8B3E), mark: 'One'),
      'bank' => (bg: const Color(0xFF3B4A5A), mark: 'Bank'),
      _ => (bg: const Color(0xFF6E6458), mark: '\$'),
    };

/// A small dot that gently pulses, for "Awaiting pro".
class PulseDot extends StatefulWidget {
  final Color color;
  const PulseDot({super.key, required this.color});

  @override
  State<PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduced(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (_, _) => Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: widget.color,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35 * (1 - _c.value)),
                spreadRadius: 5 * _c.value,
              ),
            ],
          ),
        ),
      );
}

const reminderChoices = [30, 60, 1440, 0];

/// "30 min before", "1 hour before", "1 day before".
String reminderLabel(int minutes) => switch (minutes) {
      30 => '30 min before',
      60 => '1 hour before',
      1440 => '1 day before',
      _ => 'off',
    };

/// Bottom sheet: when should we remind the client about this booking?
/// Returns the minutes picked (0 = no reminder), or null if closed.
Future<int?> showReminderSheet(BuildContext context, Map<String, dynamic> booking, int current) {
  final start = DateTime.tryParse(booking['booking_time'] ?? '')?.toLocal();
  String at(int m) {
    if (start == null || m == 0) return '';
    final t = start.subtract(Duration(minutes: m));
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    if (m >= 1440) {
      const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      return '${days[t.weekday - 1]} $hh:$mm';
    }
    return '$hh:$mm';
  }

  var picked = current;
  return showModalBottomSheet<int>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Remind me',
                style: TextStyle(
                    fontFamily: AppTheme.displayFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('We\'ll send a notification before your appointment.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            for (final m in reminderChoices)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Semantics(
                  selected: picked == m,
                  button: true,
                  child: GestureDetector(
                    onTap: () {
                      Haptics.light();
                      setSheet(() => picked = m);
                    },
                    child: AnimatedContainer(
                      duration: Motion.fast,
                      height: 56,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: picked == m ? AppColors.primarySoft : AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: picked == m ? AppColors.gold : Colors.transparent, width: 2),
                      ),
                      child: Row(children: [
                        AnimatedContainer(
                          duration: Motion.fast,
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: picked == m ? AppColors.gold : AppColors.borderStrong, width: picked == m ? 6 : 2),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(m == 0 ? 'No reminder' : reminderLabel(m).replaceFirst('min', 'minutes'),
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        ),
                        Text(at(m), style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 6),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, picked),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: const Text('Save'),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}
