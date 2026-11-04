import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../widgets/booking_bits.dart';
import '../widgets/reschedule_sheet.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart';

class ClientBookingsScreen extends StatefulWidget {
  const ClientBookingsScreen({super.key});
  @override
  State<ClientBookingsScreen> createState() => _ClientBookingsScreenState();
}

class _ClientBookingsScreenState extends State<ClientBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;
  String _q = '';
  RealtimeChannel? _channel;
  /// Cancelled on screen but not sent yet: the client has 5 seconds to undo.
  final Set<String> _undoable = {};

  @override
  void initState() {
    super.initState();
    _load();
    final uid = supabase.auth.currentUser?.id;
    if (uid != null) {
      _channel = supabase
          .channel('client_bookings_$uid')
          .onPostgresChanges(
            event: PostgresChangeEvent.all,
            schema: 'public',
            table: 'bookings',
            filter: PostgresChangeFilter(type: PostgresChangeFilterType.eq, column: 'client_id', value: uid),
            callback: (_) => _load(),
          )
          .subscribe();
    }
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await supabase
          .from('bookings')
          .select('*, services(service_name, duration_minutes, service_categories(name)), '
              'service_tiers(name, duration_minutes), booking_addons(addon_duration), '
              'profiles!bookings_provider_id_fkey(full_name, avatar_url), reviews(id)')
          .eq('client_id', supabase.auth.currentUser!.id)
          .order('booking_time', ascending: true);
      if (mounted) {
        final before = {for (final b in _bookings) b['id']: b['status']};
        final fresh = List<Map<String, dynamic>>.from(data);
        if (fresh.any((b) => before[b['id']] == 'pending' && b['status'] == 'confirmed')) Haptics.firm();
        setState(() {
          _bookings = fresh;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load your bookings.';
          _loading = false;
        });
      }
    }
  }

  bool _isUpcoming(Map<String, dynamic> b) {
    final t = DateTime.tryParse(b['booking_time'] ?? '');
    return (b['status'] == 'pending' || b['status'] == 'confirmed') &&
        t != null &&
        t.isAfter(DateTime.now().subtract(const Duration(hours: 3)));
  }

  Future<void> _cancel(Map<String, dynamic> b) async {
    final paid = paidSoFar(b) > 0;
    if (paid) {
      if (!await confirmPaidCancel(context, b, byPro: false)) return;
      if (!mounted) return;
    }
    final ok = paid ? true : await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(b['status'] == 'confirmed'
            ? 'Your pro has confirmed this booking. Their cancellation policy may apply.'
            : 'Your pro will be told you cancelled.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel booking'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    // Hide it now, send the cancellation after 5 seconds unless undone.
    final id = b['id'] as String;
    Haptics.warn();
    setState(() => _undoable.add(id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(SnackBar(
          content: Text('Cancelled: ${_BookingInfo(b).service}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ))
        .closed;
    if (reason == SnackBarClosedReason.action) {
      Haptics.light();
      if (mounted) setState(() => _undoable.remove(id));
      return;
    }
    try {
      final fee = await supabase.rpc('cancel_booking', params: {'p_booking_id': id, 'p_reason': null});
      if ((fee as num) > 0) {
        messenger.showSnackBar(
          SnackBar(content: Text('Cancelled. A late fee of \$${fee.toStringAsFixed(2)} applies.')),
        );
      }
    } on PostgrestException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
    }
    _undoable.remove(id);
    await _load();
  }

  Future<void> _remind(Map<String, dynamic> b) async {
    final current = (b['client_reminder_minutes'] as num?)?.toInt() ?? 60;
    final picked = await showReminderSheet(context, b, current);
    if (picked == null || picked == current || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => b['client_reminder_minutes'] = picked);
    try {
      await supabase.rpc('set_booking_reminder', params: {'p_booking': b['id'], 'p_minutes': picked});
      Haptics.firm();
      messenger.showSnackBar(SnackBar(
          content: Text(picked == 0 ? 'No reminder for this booking' : 'We\'ll remind you ${reminderLabel(picked)}')));
    } catch (_) {
      if (mounted) setState(() => b['client_reminder_minutes'] = current);
      messenger.showSnackBar(
          SnackBar(content: const Text('Could not save your reminder. Try again.'), backgroundColor: AppColors.error));
    }
  }

  Future<void> _reschedule(Map<String, dynamic> b) async {
    if (await showRescheduleSheet(context, b)) {
      _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Booking moved. Your pro will confirm the new time.')),
        );
      }
    }
  }

  bool _matches(Map<String, dynamic> b) {
    if (_q.isEmpty) return true;
    final i = _BookingInfo(b);
    return '${i.service} ${i.pro} ${i.ref ?? ''}'.toLowerCase().contains(_q);
  }

  @override
  Widget build(BuildContext context) {
    final shown = _bookings.where((b) => !_undoable.contains(b['id'])).toList();
    final upcoming = shown.where(_isUpcoming).where(_matches).toList();
    final past = shown.where((b) => !_isUpcoming(b)).where(_matches).toList().reversed.toList();
    const noMatch = EmptyState(
      icon: TablerIcons.search,
      title: 'No bookings match',
      message: 'Try a different service, pro or reference.',
    );

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: largeTitleBar(
          context,
          'Bookings',
          bottom: _BookingsToolbar(
            tabs: ['Upcoming${upcoming.isNotEmpty ? ' (${upcoming.length})' : ''}', 'Past'],
            onSearch: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
        ),
        body: _loading
            ? const LoadingPlaceholder()
            : _error != null
                ? EmptyState(
                    icon: TablerIcons.wifi_off,
                    title: 'Something went wrong',
                    message: _error!,
                    actionLabel: 'Try again',
                    onAction: _load,
                  )
                : TabBarView(children: [
                    _list(
                      upcoming,
                      _q.isNotEmpty
                          ? noMatch
                          : const EmptyState(
                              icon: TablerIcons.calendar_check,
                              title: 'No upcoming bookings',
                              message: 'When you book a beauty pro, your appointment shows up here.',
                            ),
                      showFind: _q.isEmpty,
                    ),
                    _list(
                      past,
                      _q.isNotEmpty
                          ? noMatch
                          : const EmptyState(
                              icon: TablerIcons.history,
                              title: 'Nothing here yet',
                              message: 'Your finished and cancelled bookings will appear here.',
                            ),
                    ),
                  ]),
      ),
    );
  }

  Widget _list(List<Map<String, dynamic>> items, Widget empty, {bool showFind = false}) {
    if (items.isEmpty) {
      return RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 60),
          empty,
          if (showFind)
            Center(
              child: FilledButton.icon(
                onPressed: () => context.go('/browse'),
                icon: const Icon(TablerIcons.search),
                label: const Text('Find a beauty pro'),
              ),
            ),
        ]),
      );
    }
    return RefreshIndicator.adaptive(
      onRefresh: _load,
      child: LayoutBuilder(builder: (context, c) {
        // A table on wide screens, cards on phones.
        final table = c.maxWidth >= 820;
        return ListView(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + tabBarSpace(context)),
          children: [
            PageWidth(
              child: table
                  ? _BookingsTable(
                      bookings: items,
                      isUpcoming: _isUpcoming,
                      onCancel: _cancel,
                      onReschedule: _reschedule,
                      onRemind: _remind,
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (items.any(_isUpcoming) && items.length < 4)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text('Swipe a booking left to reschedule or cancel',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                        ),
                      for (final b in items)
                        Padding(
                          key: ValueKey(b['id']),
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SwipeActions(
                            enabled: _isUpcoming(b),
                            onReschedule: () => _reschedule(b),
                            onCancel: () => _cancel(b),
                            child: _BookingCard(
                              booking: b,
                              upcoming: _isUpcoming(b),
                              onCancel: () => _cancel(b),
                              onReschedule: () => _reschedule(b),
                              onRemind: () => _remind(b),
                            ),
                          ),
                        ),
                    ]),
            ),
          ],
        );
      }),
    );
  }
}

/// What a booking card or table row shows, worked out once.
class _BookingInfo {
  final Map<String, dynamic> b;
  _BookingInfo(this.b);

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  String get status => b['status'] as String? ?? 'pending';
  DateTime? get when => DateTime.tryParse(b['booking_time'] ?? '')?.toLocal();
  String get pro => b['profiles']?['full_name'] ?? 'Beauty pro';
  String? get proAvatar => b['profiles']?['avatar_url'] as String?;
  String get service {
    final s = b['services']?['service_name'] ?? 'Appointment';
    final tier = b['service_tiers']?['name'];
    return tier != null ? '$s · $tier' : s;
  }

  double get _total => (b['total_price'] as num?)?.toDouble() ?? 0;
  String get price => '\$${_total.toStringAsFixed(_total % 1 == 0 ? 0 : 2)}';
  String? get ref => b['ref'] == null ? null : '#${b['ref']}';
  bool get reviewed => (b['reviews'] as List? ?? []).isNotEmpty;
  bool depositDue(bool upcoming) =>
      ((b['deposit_amount'] as num?) ?? 0) > 0 && b['deposit_paid'] != true && upcoming;

  (Color, String) get state => switch (status) {
        'confirmed' => (AppColors.info, 'Confirmed'),
        'pending' => (AppColors.goldText, b['rescheduled_at'] != null ? 'New time, awaiting pro' : 'Awaiting pro'),
        'completed' => (AppColors.textSecondary, 'Completed'),
        _ => (AppColors.error, b['no_show_by'] != null ? 'No-show' : 'Cancelled'),
      };

  String get time {
    final dt = when;
    if (dt == null) return '';
    return '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'pm' : 'am'}';
  }

  String get day => when == null ? '' : _days[when!.weekday - 1];
  String get month => when == null ? '' : _months[when!.month - 1];
  String get date => when == null ? '' : '$day, ${when!.day} $month ${when!.year}';
  String get shortDate => when == null ? '' : '$day ${when!.day} $month';
  int get reminder => (b['client_reminder_minutes'] as num?)?.toInt() ?? 60;
  String get paidLine {
    final paid = paidSoFar(b);
    if (paid > 0) return '${money(paid)} of $price';
    return b['payment_method'] == 'cash' || b['payment_method'] == null ? 'Cash' : payLabel;
  }

  String get payLabel => switch (b['payment_method']) {
        'ecocash' => 'EcoCash',
        'innbucks' => 'InnBucks',
        'onemoney' => 'OneMoney',
        'bank' => 'Bank',
        _ => 'Cash',
      };
}

typedef _Action = ({IconData icon, String label, VoidCallback onTap, bool destructive});

List<_Action> _actionsFor(BuildContext context, _BookingInfo i, bool upcoming,
        VoidCallback onCancel, VoidCallback onReschedule, [VoidCallback? onRemind]) =>
    [
      if (upcoming) ...[
        if (onRemind != null)
          (icon: TablerIcons.bell, label: 'Reminder', onTap: onRemind, destructive: false),
        (icon: TablerIcons.calendar_cog, label: 'Reschedule', onTap: onReschedule, destructive: false),
        (icon: TablerIcons.x, label: 'Cancel', onTap: onCancel, destructive: true),
      ] else ...[
        if (i.status == 'completed' && !i.reviewed)
          (icon: TablerIcons.star, label: 'Review', onTap: () => context.push('/review/${i.b['id']}'), destructive: false),
        (
          icon: TablerIcons.repeat,
          label: 'Book again',
          onTap: () => context.push('/book/${i.b['provider_id']}/${i.b['service_id']}'),
          destructive: false,
        ),
      ],
    ];

/// Phones: one card per booking.
class _BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool upcoming;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onRemind;
  const _BookingCard({
    required this.booking,
    required this.upcoming,
    required this.onCancel,
    required this.onReschedule,
    required this.onRemind,
  });

  @override
  Widget build(BuildContext context) {
    final i = _BookingInfo(booking);
    final actions = _actionsFor(context, i, upcoming, onCancel, onReschedule)
        .where((a) => !upcoming || a.label == 'Review' || a.label == 'Book again')
        .toList();
    Widget box(String l, String v) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.smAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(l, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
              const SizedBox(height: 1),
              Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
        );

    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/booking/${booking['id']}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              SizedBox(width: 54, height: 54, child: ProPhoto(name: i.pro, url: i.proAvatar, radius: 16)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.service,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(i.pro,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ]),
              ),
              const SizedBox(width: 8),
              _StatusPill(info: i),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              box('Date', i.shortDate),
              const SizedBox(width: 8),
              box('Time', i.time),
              const SizedBox(width: 8),
              box(paidSoFar(booking) > 0 ? 'Paid' : 'Pay', i.paidLine),
            ]),
            if (i.depositDue(upcoming)) ...[
              const SizedBox(height: 10),
              Text('Deposit of \$${(booking['deposit_amount'] as num).toStringAsFixed(2)} not paid yet',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warningText)),
            ],
            if (upcoming) ...[
              const SizedBox(height: 6),
              Row(children: [
                Icon(i.reminder == 0 ? TablerIcons.bell_off : TablerIcons.bell,
                    size: 16, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(children: [
                      const TextSpan(text: 'Reminder '),
                      TextSpan(
                          text: i.reminder == 0 ? 'off' : reminderLabel(i.reminder),
                          style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    ]),
                    style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                  ),
                ),
                TextButton(
                  onPressed: onRemind,
                  style: TextButton.styleFrom(
                      foregroundColor: AppColors.goldText,
                      minimumSize: const Size(0, 40),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(horizontal: 6)),
                  child: const Text('Change', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
                ),
                // Buttons as well as the swipe, for anyone who can't swipe.
                IconButton(
                  tooltip: 'Reschedule',
                  onPressed: onReschedule,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(TablerIcons.calendar_cog, size: 20, color: AppColors.textSecondary),
                ),
                IconButton(
                  tooltip: 'Cancel booking',
                  onPressed: onCancel,
                  visualDensity: VisualDensity.compact,
                  icon: Icon(TablerIcons.x, size: 20, color: AppColors.errorText),
                ),
              ]),
            ] else if (actions.isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(children: [
                for (final a in actions)
                  TextButton.icon(
                    onPressed: a.onTap,
                    icon: Icon(a.icon, size: 18),
                    label: Text(a.label),
                  ),
                const Spacer(),
                if (i.ref != null)
                  Text(i.ref!,
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.4)),
              ]),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Status pill that changes live (Awaiting pro → Confirmed). Waiting pulses.
class _StatusPill extends StatelessWidget {
  final _BookingInfo info;
  const _StatusPill({required this.info});

  @override
  Widget build(BuildContext context) {
    final (color, label) = info.state;
    return AnimatedSwitcher(
      duration: Motion.of(context, Motion.slow),
      transitionBuilder: (c, a) => FadeTransition(opacity: a, child: ScaleTransition(scale: a, child: c)),
      child: Container(
        key: ValueKey(label),
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: AppRadius.pill),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          info.status == 'pending' ? PulseDot(color: color) : Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      ),
    );
  }
}

/// Swipe left to show Reschedule and Cancel. Tapping elsewhere closes it.
class _SwipeActions extends StatefulWidget {
  final bool enabled;
  final Widget child;
  final VoidCallback onReschedule;
  final VoidCallback onCancel;
  const _SwipeActions(
      {required this.enabled, required this.child, required this.onReschedule, required this.onCancel});

  @override
  State<_SwipeActions> createState() => _SwipeActionsState();
}

class _SwipeActionsState extends State<_SwipeActions> with SingleTickerProviderStateMixin {
  static const _open = 184.0;
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.normal);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _settle(bool open) {
    if (open && _c.value < 1) Haptics.light();
    final d = Motion.reduced(context) ? Duration.zero : Motion.normal;
    _c.animateTo(open ? 1 : 0, duration: d, curve: Motion.curve);
  }

  void _run(VoidCallback f) {
    _settle(false);
    f();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    Widget action(IconData icon, String label, Color bg, Color fg, VoidCallback onTap) => Expanded(
          child: Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Material(
              color: bg,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => _run(onTap),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(icon, color: fg, size: 22),
                  const SizedBox(height: 6),
                  Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12.5)),
                ]),
              ),
            ),
          ),
        );
    return GestureDetector(
      onHorizontalDragUpdate: (d) => _c.value = (_c.value - d.delta.dx / _open).clamp(0.0, 1.0),
      onHorizontalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        _settle(v < -300 || (v <= 300 && _c.value > 0.45));
      },
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, child) => Stack(children: [
          if (_c.value > 0)
            Positioned.fill(
              child: ExcludeSemantics(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: SizedBox(
                    width: _open,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Opacity(
                        opacity: _c.value.clamp(0.0, 1.0),
                        child: Row(children: [
                          action(TablerIcons.calendar_cog, 'Reschedule', AppColors.gold, const Color(0xFF17130E),
                              widget.onReschedule),
                          action(TablerIcons.x, 'Cancel', const Color(0xFFE5484D), Colors.white, widget.onCancel),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(-_open * _c.value, 0),
            child: GestureDetector(
              onTap: _c.value > 0 ? () => _settle(false) : null,
              child: AbsorbPointer(absorbing: _c.value > 0.05, child: child),
            ),
          ),
        ]),
        child: widget.child,
      ),
    );
  }
}

/// Wide screens: all bookings in one table, like a dashboard.
class _BookingsTable extends StatelessWidget {
  final List<Map<String, dynamic>> bookings;
  final bool Function(Map<String, dynamic>) isUpcoming;
  final void Function(Map<String, dynamic>) onCancel;
  final void Function(Map<String, dynamic>) onReschedule;
  final void Function(Map<String, dynamic>) onRemind;
  const _BookingsTable({
    required this.bookings,
    required this.isUpcoming,
    required this.onCancel,
    required this.onReschedule,
    required this.onRemind,
  });

  static const _flex = [5, 3, 2, 3, 2];

  @override
  Widget build(BuildContext context) {
    final head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.4, color: AppColors.textSecondary);
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.lgAll,
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 12, 12),
          child: Row(children: [
            for (final (k, t) in ['BOOKING', 'DATE', 'REFERENCE', 'STATUS', 'PRICE'].indexed)
              Expanded(
                flex: _flex[k],
                child: Text(t, style: head, textAlign: k == 4 ? TextAlign.right : TextAlign.left),
              ),
            const SizedBox(width: 48),
          ]),
        ),
        for (final b in bookings) ...[
          Divider(height: 1, color: AppColors.border),
          _BookingRow(
            booking: b,
            upcoming: isUpcoming(b),
            onCancel: () => onCancel(b),
            onReschedule: () => onReschedule(b),
            onRemind: () => onRemind(b),
          ),
        ],
      ]),
    );
  }
}

class _BookingRow extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool upcoming;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  final VoidCallback onRemind;
  const _BookingRow({
    required this.booking,
    required this.upcoming,
    required this.onCancel,
    required this.onReschedule,
    required this.onRemind,
  });

  @override
  Widget build(BuildContext context) {
    final i = _BookingInfo(booking);
    final actions = _actionsFor(context, i, upcoming, onCancel, onReschedule, onRemind);
    final f = _BookingsTable._flex;
    final secondary = TextStyle(fontSize: 13, color: AppColors.textSecondary);

    return InkWell(
      onTap: () => context.push('/booking/${booking['id']}'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 12, 12),
        child: Row(children: [
          Expanded(
            flex: f[0],
            child: Row(children: [
              PersonAvatar(name: i.pro, url: i.proAvatar, size: 40),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(i.pro, maxLines: 1, overflow: TextOverflow.ellipsis, style: secondary),
                ]),
              ),
            ]),
          ),
          Expanded(
            flex: f[1],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(i.date, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(i.time, style: secondary),
            ]),
          ),
          Expanded(
            flex: f[2],
            child: Text(i.ref ?? '–',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary, letterSpacing: 0.3)),
          ),
          Expanded(
            flex: f[3],
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatusPill(info: i),
              if (i.depositDue(upcoming))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Deposit not paid',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning)),
                ),
            ]),
          ),
          Expanded(
            flex: f[4],
            child: Text(i.price,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ),
          SizedBox(
            width: 48,
            child: PopupMenuButton<int>(
              tooltip: 'Actions',
              icon: Icon(TablerIcons.dots, color: AppColors.textSecondary),
              // onSelected runs after the menu closes, so a pushed page isn't popped with it.
              onSelected: (k) => actions[k].onTap(),
              itemBuilder: (_) => [
                for (final (k, a) in actions.indexed)
                  PopupMenuItem<int>(
                    value: k,
                    child: Row(children: [
                      Icon(a.icon, size: 18, color: a.destructive ? AppColors.error : AppColors.textPrimary),
                      const SizedBox(width: 10),
                      Text(a.label, style: TextStyle(color: a.destructive ? AppColors.error : AppColors.textPrimary)),
                    ]),
                  ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Upcoming / Past switch under the title. Wide screens also get a search box.
class _BookingsToolbar extends StatelessWidget implements PreferredSizeWidget {
  final List<String> tabs;
  final ValueChanged<String> onSearch;
  const _BookingsToolbar({required this.tabs, required this.onSearch});

  @override
  Size get preferredSize => const Size.fromHeight(44);

  @override
  Widget build(BuildContext context) {
    final segment = Container(
      height: 36,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(999)),
      child: TabBar(tabs: [for (final t in tabs) Tab(height: 32, text: t)]),
    );
    if (!isWideLayout(context)) {
      return Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: segment);
    }
    return PageWidth(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        child: Row(children: [
          SizedBox(width: 340, child: segment),
          const Spacer(),
          SizedBox(
            width: 300,
            height: 36,
            child: TextField(
              onChanged: onSearch,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Search bookings',
                prefixIcon: Icon(TablerIcons.search, size: 18),
                contentPadding: EdgeInsets.symmetric(vertical: 8),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
