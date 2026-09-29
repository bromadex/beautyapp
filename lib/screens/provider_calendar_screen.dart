import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../widgets/reschedule_sheet.dart' show bookingMinutes;

/// Stylist's week at a glance: a day strip and a timeline of that day's bookings.
class ProviderCalendarScreen extends StatefulWidget {
  const ProviderCalendarScreen({super.key});
  @override
  State<ProviderCalendarScreen> createState() => _ProviderCalendarScreenState();
}

class _ProviderCalendarScreenState extends State<ProviderCalendarScreen> {
  static const _hourHeight = 64.0;
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  late DateTime _weekStart; // Monday
  late DateTime _day;
  bool _loading = true;
  List<Map<String, dynamic>> _bookings = [];
  Map<int, Map<String, dynamic>> _hours = {}; // weekday (0=Sun) -> availability row

  @override
  void initState() {
    super.initState();
    final n = DateTime.now();
    _day = DateTime(n.year, n.month, n.day);
    _weekStart = _day.subtract(Duration(days: _day.weekday - 1));
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final uid = supabase.auth.currentUser!.id;
    final from = _weekStart;
    final to = _weekStart.add(const Duration(days: 7));
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('bookings')
            .select('id, booking_time, status, total_price, source, walkin_name, client_id, payment_status, '
                'services(service_name, duration_minutes), service_tiers(name, duration_minutes), '
                'booking_addons(addon_duration), client:profiles!bookings_client_id_fkey(full_name)')
            .eq('provider_id', uid)
            .inFilter('status', ['pending', 'confirmed', 'completed'])
            .gte('booking_time', from.toUtc().toIso8601String())
            .lt('booking_time', to.toUtc().toIso8601String())
            .order('booking_time', ascending: true),
        supabase.from('provider_availability').select().eq('provider_id', uid),
      ]);
      _bookings = List<Map<String, dynamic>>.from(results[0] as List);
      for (final b in _bookings) {
        fillWalkin(b, 'client');
      }
      _hours = {
        for (final r in List<Map<String, dynamic>>.from(results[1] as List)) (r['day_of_week'] as num).toInt(): r,
      };
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _shiftWeek(int weeks) {
    setState(() {
      _weekStart = _weekStart.add(Duration(days: 7 * weeks));
      _day = _weekStart;
    });
    _load();
  }

  bool _sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  List<Map<String, dynamic>> _on(DateTime d) => _bookings
      .where((b) => _sameDay(DateTime.parse(b['booking_time']).toLocal(), d))
      .toList();

  int _parseHour(String? hhmm, int fallback) => hhmm == null ? fallback : int.parse(hhmm.substring(0, 2));

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    final dayBookings = _on(_day);
    final av = _hours[_day.weekday % 7];
    final working = av == null ? _hours.isEmpty : av['is_available'] == true;
    var startH = working ? _parseHour(av?['start_time'], 8) : 8;
    var endH = working ? _parseHour(av?['end_time'], 18) : 18;
    if (av?['end_time'] != null && !(av!['end_time'] as String).startsWith(RegExp(r'\d\d:00'))) endH++;
    for (final b in dayBookings) {
      final t = DateTime.parse(b['booking_time']).toLocal();
      final end = t.add(Duration(minutes: bookingMinutes(b)));
      if (t.hour < startH) startH = t.hour;
      if (end.hour + (end.minute > 0 ? 1 : 0) > endH) endH = end.hour + (end.minute > 0 ? 1 : 0);
    }
    endH = endH.clamp(startH + 1, 24);
    final dayTotal = dayBookings
        .where((b) => b['status'] != 'pending')
        .fold<num>(0, (s, b) => s + ((b['total_price'] as num?) ?? 0));

    return Scaffold(
      appBar: AppBar(
        title: Text('${_months[_weekStart.month - 1]} ${_weekStart.year}'),
        actions: [
          IconButton(
            tooltip: 'Today',
            icon: const Icon(Icons.today_rounded),
            onPressed: () {
              final n = DateTime.now();
              setState(() {
                _day = DateTime(n.year, n.month, n.day);
                _weekStart = _day.subtract(Duration(days: _day.weekday - 1));
              });
              _load();
            },
          ),
          IconButton(
            tooltip: 'All bookings',
            icon: const Icon(Icons.view_list_rounded),
            onPressed: () => context.push('/provider/bookings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add booking',
        onPressed: () async {
          await context.push('/provider/add-booking?date=${_day.toIso8601String().substring(0, 10)}');
          _load();
        },
        child: const Icon(Icons.add),
      ),
      body: Column(children: [
        // Week strip
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(children: [
            IconButton(icon: const Icon(Icons.chevron_left_rounded), onPressed: () => _shiftWeek(-1)),
            for (var i = 0; i < 7; i++)
              Expanded(child: _dayChip(_weekStart.add(Duration(days: i)), today)),
            IconButton(icon: const Icon(Icons.chevron_right_rounded), onPressed: () => _shiftWeek(1)),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          color: AppColors.surfaceMuted,
          child: Text(
            [
              '${_weekdays[_day.weekday - 1]} ${_day.day} ${_months[_day.month - 1]}',
              if (!working) 'day off',
              '${dayBookings.length} ${dayBookings.length == 1 ? 'booking' : 'bookings'}',
              if (dayTotal > 0) money(dayTotal),
            ].join(' · '),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 8, 16, 96),
                    child: SizedBox(
                      height: (endH - startH) * _hourHeight + 12,
                      child: Stack(clipBehavior: Clip.none, children: [
                        // Hour lines; tapping an empty hour adds a booking there
                        for (var h = startH; h <= endH; h++)
                          Positioned(
                            top: (h - startH) * _hourHeight,
                            left: 0,
                            right: 0,
                            height: _hourHeight,
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: h == endH
                                  ? null
                                  : () async {
                                      await context.push(
                                          '/provider/add-booking?date=${_day.toIso8601String().substring(0, 10)}&hour=$h');
                                      _load();
                                    },
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                SizedBox(
                                  width: 56,
                                  child: Transform.translate(
                                    offset: const Offset(0, -7),
                                    child: Text(
                                      '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'am' : 'pm'}',
                                      textAlign: TextAlign.right,
                                      style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(child: Container(height: 1, color: AppColors.border)),
                              ]),
                            ),
                          ),
                        // Now line
                        if (_sameDay(_day, today) && today.hour >= startH && today.hour < endH)
                          Positioned(
                            top: (today.hour - startH + today.minute / 60) * _hourHeight,
                            left: 58,
                            right: 0,
                            child: Row(children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              ),
                              Expanded(child: Container(height: 2, color: AppColors.error)),
                            ]),
                          ),
                        for (final b in dayBookings) _block(b, startH),
                      ]),
                    ),
                  ),
                ),
        ),
      ]),
    );
  }

  Widget _dayChip(DateTime d, DateTime today) {
    final selected = _sameDay(d, _day);
    final isToday = _sameDay(d, today);
    final count = _on(d).length;
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () => setState(() => _day = d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary : Colors.transparent,
          borderRadius: AppRadius.mdAll,
        ),
        child: Column(children: [
          Text(_weekdays[d.weekday - 1].substring(0, 1),
              style: TextStyle(fontSize: 11, color: selected ? Colors.white70 : AppColors.textTertiary)),
          const SizedBox(height: 2),
          Text('${d.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: selected ? Colors.white : (isToday ? AppColors.primary : AppColors.textPrimary),
              )),
          const SizedBox(height: 3),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: count == 0 ? Colors.transparent : (selected ? Colors.white : AppColors.primary),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _block(Map<String, dynamic> b, int startH) {
    final t = DateTime.parse(b['booking_time']).toLocal();
    final mins = bookingMinutes(b);
    final top = (t.hour - startH + t.minute / 60) * _hourHeight;
    final height = (mins / 60 * _hourHeight).clamp(30.0, 2000.0);
    final status = b['status'] as String;
    final color = status == 'pending'
        ? AppColors.warning
        : status == 'completed'
            ? AppColors.success
            : AppColors.primary;
    final end = t.add(Duration(minutes: mins));
    String hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';
    final service = b['service_tiers']?['name'] != null
        ? '${b['services']?['service_name']} · ${b['service_tiers']['name']}'
        : b['services']?['service_name'] ?? 'Service';
    return Positioned(
      top: top + 1,
      left: 66,
      right: 0,
      height: height - 2,
      child: GestureDetector(
        onTap: () async {
          await context.push('/booking/${b['id']}');
          _load();
        },
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
          decoration: BoxDecoration(
            color: Color.alphaBlend(color.withValues(alpha: 0.12), Colors.white),
            borderRadius: AppRadius.smAll,
            border: Border(left: BorderSide(color: color, width: 4)),
          ),
          child: ClipRect(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Text(b['client']?['full_name'] ?? 'Client',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
                ),
                if (status == 'pending')
                  const Text('NEEDS ANSWER',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: AppColors.warning)),
              ]),
              if (height > 44)
                Text('${hm(t)}–${hm(end)} · $service',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
        ),
      ),
    );
  }
}
