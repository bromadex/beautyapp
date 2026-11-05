import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/legal.dart' show openPrivacyPolicy;
import '../utils/pro_photos.dart';
import '../widgets/ui.dart';

/// The marketing page for signed-out visitors at the main web address:
/// headline, real numbers, how it works, featured pros and "Join as a pro".
/// Dark and gold whatever the appearance setting.
class LandingScreen extends StatefulWidget {
  const LandingScreen({super.key});
  @override
  State<LandingScreen> createState() => _LandingScreenState();
}

const _bg = Color(0xFF0B0A09);
const _card = Color(0xFF141210);
const _line = Color(0xFF221F1B);
const _text = Color(0xFFF5EFE6);
const _muted = Color(0xFFA39A8D);
const _gold = AppColors.gold;

class _LandingScreenState extends State<LandingScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _featured = [];
  Map<String, String> _covers = {};
  final _howKey = GlobalKey();
  final _proKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait<dynamic>([
        supabase.rpc('public_stats'),
        supabase
            .from('provider_profiles')
            .select('provider_id, title, area, average_rating, total_reviews, cities(name), '
                'profiles!inner(full_name, avatar_url, is_verified)')
            .or('is_hidden.eq.false,is_hidden.is.null')
            .not('city_id', 'is', null)
            .order('average_rating', ascending: false)
            .limit(30),
        loadCoverPhotos(),
      ]);
      _stats = Map<String, dynamic>.from(r[0] as Map);
      final covers = r[2] as Map<String, String>;
      final pros = List<Map<String, dynamic>>.from(r[1] as List).where((p) {
        final prof = p['profiles'] as Map? ?? {};
        final photo = coverFor(covers, p['provider_id'], prof['avatar_url'] as String?);
        return photo != null && (p['area'] ?? '').toString().trim().isNotEmpty;
      }).toList()
        // Reviewed pros first, then verified ones.
        ..sort((a, b) {
          int score(Map p) =>
              (((p['total_reviews'] as num?) ?? 0) > 0 ? 2 : 0) + (p['profiles']?['is_verified'] == true ? 1 : 0);
          return score(b).compareTo(score(a));
        });
      if (mounted) {
        setState(() {
          _covers = covers;
          _featured = pros.take(4).toList();
        });
      }
    } catch (_) {}
  }

  void _scrollTo(GlobalKey k) {
    final c = k.currentContext;
    if (c != null) Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
  }

  String get _prosLabel {
    final n = (_stats?['pros'] as num?)?.toInt() ?? 0;
    if (n >= 20) return '${(n ~/ 10) * 10}+';
    return n > 0 ? '$n' : '–';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: LayoutBuilder(builder: (context, box) {
        final wide = box.maxWidth >= 900;
        final pad = wide ? 48.0 : 22.0;
        return SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1240),
              child: DefaultTextStyle(
                style: const TextStyle(color: _text, fontFamily: 'Inter'),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  _top(pad, wide),
                  wide ? _heroWide(pad) : _heroPhone(pad),
                  _trust(pad, wide),
                  _how(pad, wide),
                  if (_featured.isNotEmpty) _featuredPros(pad, wide),
                  _proBand(pad, wide),
                  _footer(pad),
                ]),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _logo() => Row(mainAxisSize: MainAxisSize.min, children: [
        Image.asset('assets/branding/app_mark.png', width: 34, height: 34),
        const SizedBox(width: 10),
        const Text('BeauTap', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 19, color: _text)),
      ]);

  Widget _link(String t, VoidCallback onTap) => TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(foregroundColor: const Color(0xFFCFC6B8), textStyle: const TextStyle(fontSize: 15)),
        child: Text(t),
      );

  Widget _goldButton(String t, VoidCallback onTap, {double h = 56}) => SizedBox(
        height: h,
        child: FilledButton(
          onPressed: onTap,
          style: FilledButton.styleFrom(
            backgroundColor: _gold,
            foregroundColor: const Color(0xFF17130E),
            padding: const EdgeInsets.symmetric(horizontal: 26),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Text(t),
        ),
      );

  Widget _outlineButton(String t, VoidCallback onTap) => SizedBox(
        height: 56,
        child: OutlinedButton(
          onPressed: onTap,
          style: OutlinedButton.styleFrom(
            foregroundColor: _text,
            side: const BorderSide(color: Color(0xFF3A342C), width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 26),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          child: Text(t),
        ),
      );

  void _book() => context.go('/login');
  void _joinPro() => context.go('/register?as=pro');

  Widget _top(double pad, bool wide) => Padding(
        padding: EdgeInsets.fromLTRB(pad, 18, pad - 8, 8),
        child: Row(children: [
          _logo(),
          const Spacer(),
          if (wide) ...[
            _link('How it works', () => _scrollTo(_howKey)),
            _link('For pros', () => _scrollTo(_proKey)),
            _link('Tips', () => context.go('/tips')),
          ],
          _link('Sign in', () => context.go('/login')),
          if (wide) ...[const SizedBox(width: 8), _goldButton('Book a pro', _book, h: 44)],
        ]),
      );

  Widget _headline(double size) => Text.rich(
        TextSpan(children: [
          const TextSpan(text: 'Your next look,\n'),
          TextSpan(text: 'one tap away.', style: TextStyle(color: _gold)),
        ]),
        style: TextStyle(fontFamily: 'InterDisplay', fontSize: size, height: 1.03, fontWeight: FontWeight.w700, letterSpacing: -size * 0.03),
      );

  static const _pitch = 'Find braiders, barbers, nail techs and makeup artists near you. See their work, real prices and '
      'reviews, then book a time that suits you. Pay them directly by EcoCash or cash.';

  Widget _heroWide(double pad) => Padding(
        padding: EdgeInsets.fromLTRB(pad, 30, pad, 50),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('BEAUTY, BOOKED IN ZIMBABWE',
                  style: TextStyle(color: _gold, fontWeight: FontWeight.w600, letterSpacing: 1.6, fontSize: 13)),
              const SizedBox(height: 14),
              _headline(62),
              const SizedBox(height: 18),
              const SizedBox(width: 520, child: Text(_pitch, style: TextStyle(fontSize: 18, height: 1.5, color: Color(0xFFBDB3A4)))),
              const SizedBox(height: 26),
              Row(children: [_goldButton('Find a beauty pro', _book), const SizedBox(width: 12), _outlineButton('Join as a pro', _joinPro)]),
              const SizedBox(height: 20),
              const Text('●  Android app     ●  Works in any browser', style: TextStyle(color: Color(0xFF8F877B), fontSize: 13.5)),
            ]),
          ),
          const SizedBox(width: 40),
          SizedBox(
            width: 460,
            height: 520,
            child: Stack(clipBehavior: Clip.none, children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(230), bottom: Radius.circular(30)),
                  child: Image.asset('assets/photos/welcome_1.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.5)),
                ),
              ),
              if (((_stats?['reviews'] as num?) ?? 0) > 0)
                Positioned(
                  left: -30,
                  bottom: 60,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 12, 16, 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF191714),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF2F2A22)),
                      boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 40, offset: Offset(0, 20))],
                    ),
                    child: Row(children: [
                      const Icon(TablerIcons.star_filled, color: _gold, size: 22),
                      const SizedBox(width: 10),
                      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('${_stats?['rating'] ?? ''} average rating',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _text)),
                        Text('from ${_stats?['reviews']} client reviews', style: const TextStyle(fontSize: 12.5, color: _muted)),
                      ]),
                    ]),
                  ),
                ),
            ]),
          ),
        ]),
      );

  Widget _heroPhone(double pad) => SizedBox(
        height: 640,
        child: Stack(children: [
          Positioned.fill(
            child: Image.asset('assets/photos/welcome_1.jpg', fit: BoxFit.cover, alignment: const Alignment(0, -0.6)),
          ),
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x33000000), Color(0x000B0A09), Color(0xF20B0A09), _bg],
                  stops: [0, 0.35, 0.72, 1],
                ),
              ),
            ),
          ),
          Positioned(
            left: pad,
            right: pad,
            bottom: 24,
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _headline(38),
              const SizedBox(height: 10),
              const Text('Braiders, barbers, nail techs and makeup artists near you. Real prices, real reviews.',
                  style: TextStyle(fontSize: 15, height: 1.45, color: Color(0xFFBDB3A4))),
              const SizedBox(height: 16),
              _goldButton('Find a beauty pro', _book),
              const SizedBox(height: 10),
              _outlineButton('Join as a pro', _joinPro),
            ]),
          ),
        ]),
      );

  Widget _trust(double pad, bool wide) {
    final cities = List<String>.from(_stats?['cities'] as List? ?? const []);
    final items = [
      (_prosLabel, 'beauty pros'),
      if (_stats?['rating'] != null) ('${_stats!['rating']} ★', 'average rating'),
      (cities.isEmpty ? 'Zimbabwe' : cities.take(2).join(' · '), cities.length > 2 ? 'and ${cities.length - 2} more' : 'and growing'),
      ('\$0', 'booking fees for clients'),
    ];
    return Container(
      margin: EdgeInsets.only(top: wide ? 0 : 8),
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: 24),
      decoration: const BoxDecoration(border: Border.symmetric(horizontal: BorderSide(color: _line))),
      child: Wrap(
        alignment: WrapAlignment.spaceAround,
        runSpacing: 18,
        spacing: 24,
        children: [
          for (final (v, l) in items)
            SizedBox(
              width: wide ? 230 : 140,
              child: Column(children: [
                Text(v,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontFamily: 'InterDisplay', fontSize: wide ? 32 : 22, fontWeight: FontWeight.w700, color: _text)),
                Text(l, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: Color(0xFF8F877B))),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _section(String title, Widget child, double pad, {Key? key}) => Padding(
        key: key,
        padding: EdgeInsets.fromLTRB(pad, 44, pad, 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontFamily: 'InterDisplay', fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          const SizedBox(height: 20),
          child,
        ]),
      );

  Widget _how(double pad, bool wide) {
    const steps = [
      ('Find your pro', 'Browse by style or on the map. Every pro shows their work, prices and reviews.'),
      ('Pick a time', 'Only free times are shown. Book in a few taps, at their place or yours.'),
      ('Pay them directly', 'EcoCash, InnBucks, OneMoney or cash. BeauTap never holds your money.'),
    ];
    final cards = [
      for (final (i, s) in steps.indexed)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(24), border: Border.all(color: _line)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: _gold, borderRadius: BorderRadius.circular(12)),
              child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
            ),
            const SizedBox(height: 14),
            Text(s.$1, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text(s.$2, style: const TextStyle(fontSize: 14.5, height: 1.5, color: _muted)),
          ]),
        ),
    ];
    return _section(
      'How it works',
      wide
          ? IntrinsicHeight(
              child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final (i, c) in cards.indexed) ...[if (i > 0) const SizedBox(width: 18), Expanded(child: c)],
              ]),
            )
          : Column(children: [for (final c in cards) Padding(padding: const EdgeInsets.only(bottom: 12), child: c)]),
      pad,
      key: _howKey,
    );
  }

  Widget _featuredPros(double pad, bool wide) {
    Widget card(Map<String, dynamic> p) {
      final prof = p['profiles'] as Map? ?? {};
      final name = (prof['full_name'] ?? '').toString();
      final rating = (p['average_rating'] as num?)?.toDouble() ?? 0;
      final reviews = (p['total_reviews'] as num?)?.toInt() ?? 0;
      return Material(
        color: _card,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.go('/provider/${p['provider_id']}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: wide ? 210 : 170,
              child: ProPhoto(name: name, url: coverFor(_covers, p['provider_id'], prof['avatar_url'] as String?), radius: 0),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('$name${prof['is_verified'] == true ? ' ✔' : ''}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                Text(
                    [
                      if ((p['title'] ?? '').toString().isNotEmpty) p['title'],
                      p['area'],
                      reviews > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New',
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: _muted)),
              ]),
            ),
          ]),
        ),
      );
    }

    return _section(
      'Featured pros',
      LayoutBuilder(builder: (context, box) {
        final cols = wide ? 4 : 2;
        final w = (box.maxWidth - 16 * (cols - 1)) / cols;
        return Wrap(spacing: 16, runSpacing: 16, children: [for (final p in _featured) SizedBox(width: w, child: card(p))]);
      }),
      pad,
    );
  }

  Widget _proBand(double pad, bool wide) {
    final text = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Are you a beauty pro?',
          style: TextStyle(
              fontFamily: 'InterDisplay', fontSize: wide ? 32 : 26, fontWeight: FontWeight.w700, color: const Color(0xFF17130E), height: 1.1)),
      const SizedBox(height: 8),
      const Text(
          'Get booked by new clients, take deposits by EcoCash, send reminders and sell monthly packages. Free to start.',
          style: TextStyle(fontSize: 15.5, height: 1.45, color: Color(0xFF17130E))),
    ]);
    final button = SizedBox(
      height: 56,
      child: FilledButton(
        onPressed: _joinPro,
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF141210),
          foregroundColor: _text,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          shape: const StadiumBorder(),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        child: const Text('Join as a pro  →'),
      ),
    );
    return Container(
      key: _proKey,
      margin: EdgeInsets.fromLTRB(pad, 44, pad, 44),
      padding: EdgeInsets.symmetric(horizontal: wide ? 40 : 22, vertical: wide ? 34 : 26),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        gradient: const LinearGradient(colors: [Color(0xFFC8A15A), Color(0xFFE2BE7A)]),
      ),
      child: wide
          ? Row(children: [Expanded(child: text), const SizedBox(width: 30), button])
          : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [text, const SizedBox(height: 18), button]),
    );
  }

  Widget _footer(double pad) => Container(
        padding: EdgeInsets.fromLTRB(pad, 20, pad, 30),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: _line))),
        child: Wrap(alignment: WrapAlignment.spaceBetween, runSpacing: 10, spacing: 20, children: [
          const Text('© 2026 BeauTap · Made in Zimbabwe', style: TextStyle(color: Color(0xFF6E6458), fontSize: 13)),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (final (t, go) in <(String, VoidCallback)>[
              ('Tips', () => context.go('/tips')),
              ('Privacy', openPrivacyPolicy),
              ('Sign in', () => context.go('/login')),
            ])
              TextButton(
                onPressed: go,
                style: TextButton.styleFrom(foregroundColor: const Color(0xFF8F877B), textStyle: const TextStyle(fontSize: 13)),
                child: Text(t),
              ),
          ]),
        ]),
      );
}
