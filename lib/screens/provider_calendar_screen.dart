import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../utils/feel.dart';
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
  static const _monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December'
  ];

  Widget _summary(String value, String label) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        if (label.isNotEmpty) Text(label, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      ]);

  late DateTime _weekStart; // Monday
  late DateTime _day;
  bool _loading = true;
  List<Map<String, dynamic>> _bookings = [];
  Map<int, Map<String, dynamic>> _hours = {}; // weekday (0=Sun) -> availability row

  // Hold-and-drag to move a booking.
  String? _dragId;
  double _dragDy = 0;
  int _dragSnap = 0; // minutes moved, in 15-minute steps

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

    final hoursLabel = working && av != null
        ? '${(av['start_time'] as String).substring(0, 2)}–${(av['end_time'] as String).substring(0, 2)}'
        : 'Day off';

    return Scaffold(
      floatingActionButton: tabFab(context, FloatingActionButton(
        tooltip: 'Add booking',
        onPressed: () async {
          await context.push('/provider/add-booking?date=${_day.toIso8601String().substring(0, 10)}');
          _load();
        },
        child: const Icon(TablerIcons.plus, size: 28),
      )),
      body: Column(children: [
        ForestHeader(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 14),
          child: Column(children: [
            Row(children: [
              Expanded(
                child: Text('${_monthNames[_day.month - 1]} ${_day.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
              ),
              IconButton(
                tooltip: 'Today',
                icon: const Icon(TablerIcons.calendar_event, color: Colors.white),
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
                icon: const Icon(TablerIcons.list, color: Colors.white),
                onPressed: () => context.push('/provider/bookings'),
              ),
              IconButton(icon: const Icon(TablerIcons.chevron_left, color: Colors.white), onPressed: () => _shiftWeek(-1)),
              IconButton(icon: const Icon(TablerIcons.chevron_right, color: Colors.white), onPressed: () => _shiftWeek(1)),
            ]),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Row(children: [
                for (var i = 0; i < 7; i++) Expanded(child: _dayChip(_weekStart.add(Duration(days: i)), today)),
              ]),
            ),
          ]),
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          decoration: BoxDecoration(
            color: AppColors.card,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(children: [
            Expanded(child: _summary('${dayBookings.length}', dayBookings.length == 1 ? 'booking' : 'bookings')),
            Expanded(child: _summary(money(dayTotal), 'total')),
            Expanded(child: _summary(hoursLabel, working ? 'hours' : '')),
          ]),
        ),
        if (dayBookings.any(_canMove))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Hold a booking and drag it to move it',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ),
        Expanded(
          child: _loading
              ? const LoadingPlaceholder()
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(0, 8, 16, 80 + tabBarSpace(context)),
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
                                      style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary),
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
                                decoration: BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                              ),
                              Expanded(child: Container(height: 2, color: AppColors.error)),
                            ]),
                          ),
                        for (final b in dayBookings.where((b) => b['id'] == _dragId)) _ghost(b, startH),
                        for (final b in dayBookings.where((b) => b['id'] != _dragId)) _block(b, startH),
                        // The dragged booking on top of the others.
                        for (final b in dayBookings.where((b) => b['id'] == _dragId)) _block(b, startH),
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
    final count = _on(d).length;
    final av = _hours[d.weekday % 7];
    final off = av != null && av['is_available'] != true;
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () => setState(() => _day = d),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.gold : Colors.transparent,
          borderRadius: AppRadius.mdAll,
        ),
        child: Column(children: [
          Text(_weekdays[d.weekday - 1],
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? const Color(0xFF17130E) : (off ? const Color(0xFF8F877B) : const Color(0xFFCFC6B8)))),
          const SizedBox(height: 4),
          Text('${d.day}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: selected ? const Color(0xFF17130E) : (off ? const Color(0xFF8F877B) : Colors.white),
              )),
          const SizedBox(height: 4),
          if (off && count == 0)
            Text('OFF',
                style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                    color: selected ? const Color(0xFF4A4238) : const Color(0xFF8F877B)))
          else
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: count == 0 ? Colors.transparent : (selected ? const Color(0xFF17130E) : AppColors.gold),
              ),
            ),
        ]),
      ),
    );
  }

  bool _canMove(Map<String, dynamic> b) =>
      (b['status'] == 'pending' || b['status'] == 'confirmed') &&
      DateTime.parse(b['booking_time']).isAfter(DateTime.now());

  String _hm(DateTime x) => '${x.hour.toString().padLeft(2, '0')}:${x.minute.toString().padLeft(2, '0')}';

  Future<void> _confirmMove(Map<String, dynamic> b, DateTime from, DateTime to) async {
    final name = (b['client']?['full_name'] ?? 'the client').toString();
    final first = name.split(' ').first;
    String label(DateTime d) => '${_weekdays[d.weekday - 1]} ${d.day} ${_monthNames[d.month - 1].substring(0, 3)} · ${_hm(d)}';
    final ok = await showModalBottomSheet<bool>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Move this booking?',
                style: TextStyle(
                    fontFamily: AppTheme.displayFamily,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text(isManualBooking(b)
                    ? 'This is a walk-in you added, so only your calendar changes.'
                    : '$first gets a notification with the new time and can move it again if it doesn\'t suit them.',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: AppColors.textSecondary)),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(18)),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('From', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(label(from),
                        style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textSecondary,
                            decoration: TextDecoration.lineThrough)),
                  ]),
                ),
                Icon(TablerIcons.arrow_right, color: AppColors.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('To', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(label(to),
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: Text('Move to ${_hm(to)}'),
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text('Keep ${_hm(from)}')),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await supabase.rpc('reschedule_booking', params: {
        'p_booking_id': b['id'],
        'p_new_time': to.toUtc().toIso8601String(),
      });
      Haptics.firm();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Moved to ${_hm(to)}${isManualBooking(b) ? '' : '. $first has been told.'}')));
      }
    } on PostgrestException catch (e) {
      Haptics.warn();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
    _load();
  }

  Widget _block(Map<String, dynamic> b, int startH) {
    final t = DateTime.parse(b['booking_time']).toLocal();
    final mins = bookingMinutes(b);
    final top = (t.hour - startH + t.minute / 60) * _hourHeight;
    final height = (mins / 60 * _hourHeight).clamp(30.0, 2000.0);
    final status = b['status'] as String;
    final color = StatusColors.strip(status);
    final bg = StatusColors.background(status);
    final dragging = _dragId == b['id'];
    final shownStart = dragging ? t.add(Duration(minutes: _dragSnap)) : t;
    final end = shownStart.add(Duration(minutes: mins));
    final service = b['service_tiers']?['name'] != null
        ? '${b['services']?['service_name']} · ${b['service_tiers']['name']}'
        : b['services']?['service_name'] ?? 'Service';
    final movable = _canMove(b);
    final card = Container(
      padding: const EdgeInsets.fromLTRB(10, 6, 8, 6),
      decoration: BoxDecoration(
        color: dragging ? AppColors.card : bg,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: dragging ? AppColors.gold : color, width: 4)),
        boxShadow: dragging
            ? const [BoxShadow(color: Color(0x47140E06), blurRadius: 30, offset: Offset(0, 14))]
            : null,
      ),
      child: ClipRect(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(b['client']?['full_name'] ?? 'Client',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5, color: AppColors.textPrimary)),
            ),
            if (status == 'pending' && !dragging)
              Text('pending',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.warningText)),
          ]),
          if (height > 44)
            Text('${_hm(shownStart)}–${_hm(end)} · $service',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 13,
                    color: dragging ? AppColors.goldText : StatusColors.foreground(status),
                    fontWeight: FontWeight.w500)),
        ]),
      ),
    );
    final snapDy = _dragSnap / 60 * _hourHeight;
    return Positioned(
      // Keyed so the drag survives this block moving to the top of the stack.
      key: ValueKey('block-${b['id']}'),
      top: top + 1 + (dragging ? _dragDy : 0),
      left: 66,
      right: 0,
      height: height - 2,
      child: GestureDetector(
        onTap: () async {
          await context.push('/booking/${b['id']}');
          _load();
        },
        onLongPressStart: !movable
            ? null
            : (_) {
                Haptics.firm();
                setState(() {
                  _dragId = b['id'] as String;
                  _dragDy = 0;
                  _dragSnap = 0;
                });
              },
        onLongPressMoveUpdate: !movable
            ? null
            : (d) {
                final snap = ((d.offsetFromOrigin.dy / _hourHeight * 60) / 15).round() * 15;
                if (snap != _dragSnap) Haptics.light();
                setState(() {
                  _dragDy = d.offsetFromOrigin.dy;
                  _dragSnap = snap;
                });
              },
        onLongPressEnd: !movable
            ? null
            : (_) {
                final moved = _dragSnap;
                setState(() => _dragId = null);
                if (moved == 0) return;
                final to = t.add(Duration(minutes: moved));
                if (to.isBefore(DateTime.now())) {
                  Haptics.warn();
                  ScaffoldMessenger.of(context)
                      .showSnackBar(const SnackBar(content: Text('That time has already passed.')));
                  return;
                }
                _confirmMove(b, t, to);
              },
        child: dragging
            ? Stack(clipBehavior: Clip.none, children: [
                Positioned.fill(child: Transform.rotate(angle: -0.02, child: Transform.scale(scale: 1.03, child: card))),
                // Gold line and time where it will land, drawn on top of the card.
                Positioned(
                  top: snapDy - _dragDy - 2,
                  left: -10,
                  right: 0,
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle)),
                    Expanded(child: Container(height: 2, color: AppColors.gold)),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                      child: Text('${_hm(shownStart)} – ${_hm(end)}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
                    ),
                  ]),
                ),
              ])
            : card,
      ),
    );
  }

  /// Where the dragged booking was, shown as a dashed outline.
  Widget _ghost(Map<String, dynamic> b, int startH) {
    final t = DateTime.parse(b['booking_time']).toLocal();
    final top = (t.hour - startH + t.minute / 60) * _hourHeight;
    final height = (bookingMinutes(b) / 60 * _hourHeight).clamp(30.0, 2000.0);
    return Positioned(
      key: ValueKey('ghost-${b['id']}'),
      top: top + 1,
      left: 66,
      right: 0,
      height: height - 2,
      child: IgnorePointer(
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.gold.withValues(alpha: 0.7), width: 1.5),
            color: AppColors.gold.withValues(alpha: 0.06),
          ),
          alignment: Alignment.center,
          child: Text('was ${_hm(t)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.goldText)),
        ),
      ),
    );
  }
}
