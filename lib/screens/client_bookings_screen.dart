import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../widgets/booking_card.dart';

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
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('client_bookings')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'client_id',
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
              '*, services(service_name, duration_minutes, service_categories(name, icon)), profiles!bookings_provider_id_fkey(full_name)')
          .eq('client_id', supabase.auth.currentUser!.id)
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

  Future<void> _cancel(String bookingId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Cancel Booking?'),
        content: const Text('Are you sure you want to cancel this booking?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('No')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              child: const Text('Cancel Booking')),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('bookings')
          .update({'status': 'cancelled', 'cancel_reason': 'Cancelled by client'})
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
        appBar: AppBar(title: const Text('My Bookings')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Bookings')),
      body: _bookings.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('No bookings yet'),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => context.go('/home'),
                    child: const Text('Find a Stylist'),
                  ),
                ],
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _bookings.length,
              separatorBuilder: (_, __) => const SizedBox(height: 10),
              itemBuilder: (_, i) {
                final b = _bookings[i];
                // TODO: Fetch actual unread count per booking
                final unreadCount = 0;
                return BookingCard(
                  booking: b,
                  isClient: true,
                  unreadCount: unreadCount,
                  onCancel: b['status'] == 'pending'
                      ? () => _cancel(b['id'])
                      : null,
                );
              },
            ),
    );
  }
}