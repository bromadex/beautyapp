import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../widgets/booking_card.dart';
import '../theme.dart';

class ProviderBookingsScreen extends StatefulWidget {
  const ProviderBookingsScreen({super.key});
  @override
  State<ProviderBookingsScreen> createState() =>
      _ProviderBookingsScreenState();
}

class _ProviderBookingsScreenState extends State<ProviderBookingsScreen> {
  List<Map<String, dynamic>> _bookings = [];
  bool _loading = true;
  String? _error;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('provider_bookings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: supabase.auth.currentUser!.id,
          ),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await supabase
          .from('bookings')
          .select(
              '*, services(service_name, duration_minutes, service_categories(name, icon)), profiles!bookings_client_id_fkey(full_name, phone)')
          .eq('provider_id', supabase.auth.currentUser!.id)
          .order('booking_time', ascending: false);

      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  /// Accepting bookings requires an active subscription:
  /// $3 activation (includes first month), then $5/month.
  /// Declining is always allowed.
  Future<bool> _canAcceptBooking() async {
    final userId = supabase.auth.currentUser!.id;
    try {
      final sub = await supabase
          .from('subscriptions')
          .select('status, end_date')
          .eq('provider_id', userId)
          .maybeSingle();
      if (sub == null || sub['status'] != 'active') return false;
      final end = DateTime.tryParse(sub['end_date'] ?? '');
      return end != null && end.isAfter(DateTime.now());
    } catch (_) {
      // Subscription table unreachable — don't block providers
      return true;
    }
  }

  Future<void> _respond(String bookingId, bool accept) async {
    if (accept && !await _canAcceptBooking()) {
      if (!mounted) return;
      final activate = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          icon: Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.rocket_launch_rounded,
                color: AppColors.primary, size: 32),
          ),
          title: const Text('Activate to Accept Bookings'),
          content: const Text(
              'Activate your account for \$3 — that covers your whole first month, then it\'s just \$5/month. You keep 100% of what you earn, no commission.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Not now')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Activate — \$3')),
          ],
        ),
      );
      if (activate == true && mounted) context.push('/provider/subscription');
      return;
    }

    await supabase.from('bookings').update({
      'status': accept ? 'confirmed' : 'cancelled',
      if (!accept) 'cancel_reason': 'Declined by provider'
    }).eq('id', bookingId);
    _load();
  }

  Future<void> _markCompleted(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_circle_outline,
              color: AppColors.success, size: 32),
        ),
        title: const Text('Mark as Completed?'),
        content: const Text('Confirm the service has been delivered.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not yet')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Yes, Completed')),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('bookings')
          .update({'status': 'completed'})
          .eq('id', bookingId);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking Requests')),
        body: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline,
                      size: 48, color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(_error!,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final pending = _bookings.where((b) => b['status'] == 'pending').toList();
    final confirmed =
        _bookings.where((b) => b['status'] == 'confirmed').toList();
    final past = _bookings
        .where((b) => b['status'] == 'completed' || b['status'] == 'cancelled')
        .toList();

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Booking Requests'),
          bottom: TabBar(
            tabs: [
              Tab(text: 'Pending (${pending.length})'),
              Tab(text: 'Confirmed (${confirmed.length})'),
              const Tab(text: 'Past'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            BookingList(
              bookings: pending,
              isProvider: true,
              onAccept: (id) => _respond(id, true),
              onDecline: (id) => _respond(id, false),
            ),
            BookingList(
              bookings: confirmed,
              isProvider: true,
              onComplete: _markCompleted,
            ),
            BookingList(bookings: past, isProvider: true),
          ],
        ),
      ),
    );
  }
}
