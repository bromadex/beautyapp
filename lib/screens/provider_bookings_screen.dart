import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../widgets/booking_card.dart';

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

  Future<void> _respond(String bookingId, bool accept) async {
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              Text(_error!),
              ElevatedButton(onPressed: _load, child: const Text('Retry')),
            ],
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