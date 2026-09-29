import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/reschedule_sheet.dart';
import '../widgets/ui.dart';

class ClientBookingsScreen extends StatefulWidget {
  const ClientBookingsScreen({super.key});
  @override
  State<ClientBookingsScreen> createState() => _ClientBookingsScreenState();
}

class _ClientBookingsScreenState extends State<ClientBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;
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
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this booking?'),
        content: Text(b['status'] == 'confirmed'
            ? 'Your stylist has confirmed this booking. Their cancellation policy may apply.'
            : 'Your stylist will be told you cancelled.'),
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
          const SnackBar(content: Text('Booking moved. Your stylist will confirm the new time.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final upcoming = _bookings.where(_isUpcoming).toList();
    final past = _bookings.where((b) => !_isUpcoming(b)).toList().reversed.toList();

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Bookings'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Upcoming${upcoming.isNotEmpty ? ' (${upcoming.length})' : ''}'),
              const Tab(text: 'Past'),
            ],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
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
                      const EmptyState(
                        icon: TablerIcons.calendar_check,
                        title: 'No upcoming bookings',
                        message: 'When you book a stylist, your appointment shows up here.',
                      ),
                      showFind: true,
                    ),
                    _list(
                      past,
                      const EmptyState(
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
      return RefreshIndicator(
        onRefresh: _load,
        child: ListView(children: [
          const SizedBox(height: 60),
          empty,
          if (showFind)
            Center(
              child: FilledButton.icon(
                onPressed: () => context.go('/browse'),
                icon: const Icon(TablerIcons.search),
                label: const Text('Find a stylist'),
              ),
            ),
        ]),
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _ReceiptCard(
              booking: items[i],
              upcoming: _isUpcoming(items[i]),
              onCancel: () => _cancel(items[i]),
              onReschedule: () => _reschedule(items[i]),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool upcoming;
  final VoidCallback onCancel;
  final VoidCallback onReschedule;
  const _ReceiptCard(
      {required this.booking, required this.upcoming, required this.onCancel, required this.onReschedule});

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final status = b['status'] as String? ?? 'pending';
    final dt = DateTime.tryParse(b['booking_time'] ?? '')?.toLocal();
    final stylist = b['profiles']?['full_name'] ?? 'Stylist';
    final service = b['services']?['service_name'] ?? 'Appointment';
    final tier = b['service_tiers']?['name'];
    final total = (b['total_price'] as num?)?.toDouble() ?? 0;
    final reviewed = (b['reviews'] as List? ?? []).isNotEmpty;
    final depositDue = ((b['deposit_amount'] as num?) ?? 0) > 0 && b['deposit_paid'] != true && upcoming;
    final noShow = b['no_show_by'] != null;

    final (Color color, String label) = switch (status) {
      'confirmed' => (AppColors.success, 'Confirmed'),
      'pending' => (AppColors.warning, b['rescheduled_at'] != null ? 'New time — awaiting stylist' : 'Awaiting stylist'),
      'completed' => (AppColors.info, 'Completed'),
      _ => (AppColors.error, noShow ? 'No-show' : 'Cancelled'),
    };

    final hh = dt == null ? '' : '${dt.hour % 12 == 0 ? 12 : dt.hour % 12}:${dt.minute.toString().padLeft(2, '0')} ${dt.hour >= 12 ? 'pm' : 'am'}';

    return Card(
      child: InkWell(
        onTap: () => context.push('/booking/${b['id']}'),
        child: IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Container(width: 5, color: color),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Pill(label: label, color: color),
                    const Spacer(),
                    if (b['ref'] != null)
                      Text('#${b['ref']}',
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.textTertiary, letterSpacing: 0.5)),
                  ]),
                  const SizedBox(height: 12),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 52,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.smAll),
                      child: Column(children: [
                        Text(dt == null ? '' : _months[dt.month - 1],
                            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: AppColors.primary)),
                        Text(dt == null ? '–' : '${dt.day}',
                            style: const TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.1)),
                      ]),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('$service${tier != null ? ' · $tier' : ''}',
                            style: Theme.of(context).textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${dt == null ? '' : '${_days[dt.weekday - 1]} · $hh · '}$stylist',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ]),
                    ),
                    Text('\$${total.toStringAsFixed(total % 1 == 0 ? 0 : 2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  ]),
                  if (depositDue) ...[
                    const SizedBox(height: 10),
                    Text('Deposit of \$${(b['deposit_amount'] as num).toStringAsFixed(2)} not paid yet',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.warning)),
                  ],
                  const SizedBox(height: 6),
                  const Divider(),
                  Row(children: [
                    if (upcoming) ...[
                      TextButton.icon(
                        onPressed: onReschedule,
                        icon: const Icon(TablerIcons.calendar_cog, size: 18),
                        label: const Text('Reschedule'),
                      ),
                      TextButton(
                        onPressed: onCancel,
                        style: TextButton.styleFrom(foregroundColor: AppColors.error),
                        child: const Text('Cancel'),
                      ),
                    ] else ...[
                      if (status == 'completed' && !reviewed)
                        TextButton.icon(
                          onPressed: () => context.push('/review/${b['id']}'),
                          icon: const Icon(TablerIcons.star, size: 18),
                          label: const Text('Review'),
                        ),
                      TextButton.icon(
                        onPressed: () => context.push('/book/${b['provider_id']}/${b['service_id']}'),
                        icon: const Icon(TablerIcons.repeat, size: 18),
                        label: const Text('Book again'),
                      ),
                    ],
                    const Spacer(),
                    const Icon(TablerIcons.chevron_right, color: AppColors.textTertiary),
                  ]),
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
