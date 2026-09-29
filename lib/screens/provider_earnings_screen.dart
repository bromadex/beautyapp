import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../services/earnings_service.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../utils/pay_methods.dart';
import '../widgets/ui.dart';

/// What the pro has received, from payments they confirmed and bookings
/// they marked as paid. Their own records; BeauTap takes no commission.
class ProviderEarningsScreen extends StatefulWidget {
  const ProviderEarningsScreen({super.key});

  @override
  State<ProviderEarningsScreen> createState() => _ProviderEarningsScreenState();
}

enum _Period { week, month, year, all }

class _ProviderEarningsScreenState extends State<ProviderEarningsScreen> {
  Earnings? _data;
  String? _error;
  _Period _period = _Period.month;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final d = await EarningsService.load();
      if (mounted) {
        setState(() {
          _data = d;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load your earnings. Check your connection.');
    }
  }

  /// Start of the chosen period and of the one before it.
  (DateTime start, DateTime prevStart) get _range {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return switch (_period) {
      _Period.week => (
          today.subtract(Duration(days: today.weekday - 1)),
          today.subtract(Duration(days: today.weekday - 1 + 7))
        ),
      _Period.month => (DateTime(now.year, now.month), DateTime(now.year, now.month - 1)),
      _Period.year => (DateTime(now.year), DateTime(now.year - 1)),
      _Period.all => (DateTime(2000), DateTime(2000)),
    };
  }

  String get _periodLabel => switch (_period) {
        _Period.week => 'this week',
        _Period.month => 'this month',
        _Period.year => 'this year',
        _Period.all => 'in total',
      };

  String get _prevLabel => switch (_period) {
        _Period.week => 'Last week',
        _Period.month => 'Last month',
        _Period.year => 'Last year',
        _Period.all => '',
      };

  String _dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return '${_days[d.weekday - 1]} ${d.day} ${_months[d.month - 1]}${d.year != now.year ? ' ${d.year}' : ''}';
  }

  IconData _methodIcon(String m) => switch (m) {
        'ecocash' => TablerIcons.device_mobile,
        'innbucks' => TablerIcons.wallet,
        'onemoney' => TablerIcons.device_mobile_dollar,
        'bank' => TablerIcons.building_bank,
        _ => TablerIcons.cash,
      };

  String _kindLabel(EarningEntry e) => switch (e.kind) {
        'deposit' => 'Deposit · ${payMethodLabel(e.method)}',
        'balance' => 'Balance · ${payMethodLabel(e.method)}',
        'full' => payMethodLabel(e.method),
        _ => 'Marked paid · ${payMethodLabel(e.method)}',
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: _error != null
          ? EmptyState(
              icon: TablerIcons.wifi_off,
              title: 'Can\'t load earnings',
              message: _error!,
              actionLabel: 'Try again',
              onAction: _load,
            )
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _body(_data!)),
    );
  }

  Widget _body(Earnings d) {
    final (start, prevStart) = _range;
    final list = d.entries.where((e) => !e.when.isBefore(start)).toList();
    final total = list.fold(0.0, (s, e) => s + e.amount);
    final prev = _period == _Period.all ? 0.0 : d.between(prevStart, start);

    final byMethod = <String, double>{};
    for (final e in list) {
      byMethod[e.method] = (byMethod[e.method] ?? 0) + e.amount;
    }
    final methods = byMethod.entries.toList()..sort((a, b) => b.value.compareTo(a.value));

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final (p, label) in const [
              (_Period.week, 'This week'),
              (_Period.month, 'This month'),
              (_Period.year, 'This year'),
              (_Period.all, 'All time'),
            ]) ...[
              ChoiceChip(
                label: Text(label),
                selected: _period == p,
                onSelected: (_) => setState(() => _period = p),
              ),
              const SizedBox(width: 8),
            ],
          ]),
        ),
        const SizedBox(height: 12),

        // Total for the period
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.xlAll),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Received $_periodLabel',
                style: const TextStyle(color: AppColors.goldLight, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(money(total),
                style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
            const SizedBox(height: 8),
            Text(
              [
                '${list.length} ${list.length == 1 ? 'payment' : 'payments'}',
                if (_period != _Period.all) '$_prevLabel ${money(prev)}',
              ].join('  ·  '),
              style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
            ),
          ]),
        ),

        if (d.toCheck.isNotEmpty) ...[
          const SizedBox(height: 12),
          SoftBanner(
            icon: TablerIcons.cash_banknote,
            color: AppColors.warning,
            title: '${d.toCheck.length} ${d.toCheck.length == 1 ? 'payment' : 'payments'} to check',
            message: 'Clients say they\'ve paid. Check your messages and confirm.',
            actionLabel: 'Check',
            onTap: () => context.push('/booking/${d.toCheck.first}').then((_) => _load()),
          ),
        ],

        if (methods.length > 1) ...[
          const SizedBox(height: 20),
          const _Heading('How you were paid'),
          const SizedBox(height: 8),
          _Panel(
            child: Column(children: [
              for (final m in methods)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(children: [
                    Icon(_methodIcon(m.key), size: 18, color: AppColors.primary),
                    const SizedBox(width: 10),
                    SizedBox(width: 96, child: Text(payMethodLabel(m.key))),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: AppRadius.pill,
                        child: LinearProgressIndicator(
                          value: total == 0 ? 0 : m.value / total,
                          minHeight: 8,
                          backgroundColor: AppColors.primarySoft,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      width: 64,
                      child: Text(money(m.value),
                          textAlign: TextAlign.right, style: const TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ]),
                ),
            ]),
          ),
        ],

        if (d.owed.isNotEmpty) ...[
          const SizedBox(height: 20),
          _Heading('Still to collect · ${money(d.owedTotal)}'),
          const SizedBox(height: 4),
          const Text('Finished appointments that aren\'t marked as paid yet.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          _Panel(
            padding: EdgeInsets.zero,
            child: Column(children: [
              for (final o in d.owed.take(5))
                _Row(
                  icon: TablerIcons.hourglass_low,
                  iconColor: AppColors.warningText,
                  title: o.client,
                  subtitle: '${o.service} · ${_dayLabel(o.when)}',
                  amount: money(o.amount),
                  onTap: () => context.push('/booking/${o.bookingId}').then((_) => _load()),
                ),
            ]),
          ),
        ],

        const SizedBox(height: 20),
        const _Heading('Payments'),
        const SizedBox(height: 8),
        if (list.isEmpty)
          _Panel(
            child: Column(children: [
              const Icon(TablerIcons.receipt, size: 32, color: AppColors.textTertiary),
              const SizedBox(height: 8),
              Text('No payments $_periodLabel', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              const Text(
                'When you confirm a payment, or mark a booking as paid, it shows here.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
            ]),
          )
        else
          ..._grouped(list),

        const SizedBox(height: 20),
        const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(TablerIcons.rosette_discount_check, size: 18, color: AppColors.success),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'You keep 100% of what clients pay you. BeauTap takes no commission and never holds your money.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
            ),
          ),
        ]),
      ],
    );
  }

  List<Widget> _grouped(List<EarningEntry> list) {
    final out = <Widget>[];
    String? day;
    var rows = <Widget>[];
    var dayTotal = 0.0;
    void flush() {
      final d = day;
      if (d == null) return;
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
        child: Row(children: [
          Expanded(child: Text(d, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
          Text(money(dayTotal), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
        ]),
      ));
      out.add(_Panel(padding: EdgeInsets.zero, child: Column(children: rows)));
      out.add(const SizedBox(height: 8));
    }

    for (final e in list) {
      final label = _dayLabel(e.when);
      if (label != day) {
        flush();
        day = label;
        rows = [];
        dayTotal = 0;
      }
      dayTotal += e.amount;
      rows.add(_Row(
        icon: _methodIcon(e.method),
        iconColor: AppColors.primary,
        title: e.client,
        subtitle: '${e.service} · ${_kindLabel(e)}',
        amount: money(e.amount),
        onTap: () => context.push('/booking/${e.bookingId}').then((_) => _load()),
      ));
    }
    flush();
    return out;
  }
}

class _Heading extends StatelessWidget {
  final String text;
  const _Heading(this.text);
  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleMedium);
}

class _Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const _Panel({required this.child, this.padding = const EdgeInsets.all(14)});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.border),
        ),
        child: child,
      );
}

class _Row extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String amount;
  final VoidCallback onTap;
  const _Row({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.smAll),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 8),
            Text(amount, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ]),
        ),
      );
}
