import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../theme.dart';
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
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(data);
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
    if (paidSoFar(b) > 0) {
      if (!await confirmPaidCancel(context, b, byPro: false)) return;
      if (!mounted) return;
    }
    final ok = paidSoFar(b) > 0 ? true : await showDialog<bool>(
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
    if (ok != true) return;
    try {
      final fee = await supabase.rpc('cancel_booking', params: {'p_booking_id': b['id'], 'p_reason': null});
      if (mounted && (fee as num) > 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cancelled. A late fee of \$${fee.toStringAsFixed(2)} applies.')),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
    _load();
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
    final upcoming = _bookings.where(_isUpcoming).where(_matches).toList();
    final past = _bookings.where((b) => !_isUpcoming(b)).where(_matches).toList().reversed.toList();
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
                    )
                  : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final b in items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _BookingCard(
                            booking: b,
                            upcoming: _isUpcoming(b),
                            onCancel: () => _cancel(b),
                            onReschedule: () => _reschedule(b),
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
        'confirmed' => (AppColors.success, 'Confirmed'),
        'pending' => (AppColors.warning, b['rescheduled_at'] != null ? 'New time, awaiting pro' : 'Awaiting pro'),
        'completed' => (AppColors.info, 'Completed'),
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
}

typedef _Action = ({IconData icon, String label, VoidCallback onTap, bool destructive});

List<_Action> _actionsFor(BuildContext context, _BookingInfo i, bool upcoming,
        VoidCallback onCancel, VoidCallback onReschedule) =>
    [
      if (upcoming) ...[
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
  const _BookingCard(
      {required this.booking, required this.upcoming, required this.onCancel, required this.onReschedule});

  @override
  Widget build(BuildContext context) {
    final i = _BookingInfo(booking);
    final (color, label) = i.state;
    final actions = _actionsFor(context, i, upcoming, onCancel, onReschedule);

    return Card(
      child: InkWell(
        onTap: () => context.push('/booking/${booking['id']}'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _DateTile(month: i.month, day: i.when?.day),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(i.service,
                      style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  _Meta(icon: TablerIcons.clock, text: '${i.day} · ${i.time}'),
                  const SizedBox(height: 2),
                  _Meta(icon: TablerIcons.user, text: i.pro),
                ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(i.price, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 6),
                Pill(label: label, color: color),
              ]),
            ]),
            if (i.depositDue(upcoming)) ...[
              const SizedBox(height: 10),
              Text('Deposit of \$${(booking['deposit_amount'] as num).toStringAsFixed(2)} not paid yet',
                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning)),
            ],
            const SizedBox(height: 10),
            Divider(height: 1, color: AppColors.border),
            Row(children: [
              for (final a in actions)
                TextButton.icon(
                  onPressed: a.onTap,
                  style: a.destructive ? TextButton.styleFrom(foregroundColor: AppColors.error) : null,
                  icon: Icon(a.icon, size: 18),
                  label: Text(a.label),
                ),
              const Spacer(),
              if (i.ref != null)
                Text(i.ref!,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.4)),
            ]),
          ]),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String month;
  final int? day;
  const _DateTile({required this.month, required this.day});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.smAll),
      child: Column(children: [
        Text(month, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
        Text(day == null ? '–' : '$day',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.1)),
      ]),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Meta({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 5),
        Expanded(
          child: Text(text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
        ),
      ]);
}

/// Wide screens: all bookings in one table, like a dashboard.
class _BookingsTable extends StatelessWidget {
  final List<Map<String, dynamic>> bookings;
  final bool Function(Map<String, dynamic>) isUpcoming;
  final void Function(Map<String, dynamic>) onCancel;
  final void Function(Map<String, dynamic>) onReschedule;
  const _BookingsTable(
      {required this.bookings, required this.isUpcoming, required this.onCancel, required this.onReschedule});

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
  const _BookingRow(
      {required this.booking, required this.upcoming, required this.onCancel, required this.onReschedule});

  @override
  Widget build(BuildContext context) {
    final i = _BookingInfo(booking);
    final (color, label) = i.state;
    final actions = _actionsFor(context, i, upcoming, onCancel, onReschedule);
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
              Pill(label: label, color: color),
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
