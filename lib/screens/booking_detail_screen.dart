import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  const BookingDetailScreen({super.key, required this.bookingId});

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen> {
  Map<String, dynamic>? _booking;
  bool _loading = true;
  String? _error;
  bool _isProvider = false;
  RealtimeChannel? _channel;

  @override
  void initState() {
    super.initState();
    _load();
    _subscribeRealtime();
  }

  void _subscribeRealtime() {
    _channel = supabase
        .channel('booking_detail_${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.bookingId,
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
    setState(() { _loading = true; _error = null; });
    try {
      final userId = supabase.auth.currentUser!.id;

      final data = await supabase
          .from('bookings')
          .select('''
            *,
            services(service_name, duration_minutes, price,
              service_categories(name, icon)),
            client:profiles!bookings_client_id_fkey(full_name, phone, location),
            provider:profiles!bookings_provider_id_fkey(full_name, phone)
          ''')
          .eq('id', widget.bookingId)
          .maybeSingle();

      if (data == null) {
        if (mounted) setState(() { _error = 'Booking not found'; _loading = false; });
        return;
      }

      if (mounted) {
        setState(() {
          _booking    = data;
          _isProvider = data['provider_id'] == userId;
          _loading    = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  // ── Navigation ──────────────────────────────────────────

  Future<void> _openMaps(String address) async {
    final encoded = Uri.encodeComponent(address);
    final googleUrl = Uri.parse('https://www.google.com/maps/search/?api=1&query=$encoded');
    final geoUrl    = Uri.parse('geo:0,0?q=$encoded');

    if (await canLaunchUrl(googleUrl)) {
      await launchUrl(googleUrl, mode: LaunchMode.externalApplication);
    } else if (await canLaunchUrl(geoUrl)) {
      await launchUrl(geoUrl, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open maps')),
        );
      }
    }
  }

  // ── Status updates (provider only) ─────────────────────

  Future<void> _markArrived() async {
    await supabase.from('bookings').update({
      'provider_arrived_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.bookingId);
    _load();
  }

  Future<void> _markStarted() async {
    await supabase.from('bookings').update({
      'service_started_at': DateTime.now().toIso8601String(),
      'status':             'confirmed',
    }).eq('id', widget.bookingId);
    _load();
  }

  Future<void> _markCompleted() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Complete Service?'),
        content: const Text('Confirm the service has been fully delivered.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Yes, Done')),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('bookings').update({
        'status':               'completed',
        'service_completed_at': DateTime.now().toIso8601String(),
      }).eq('id', widget.bookingId);
      _load();
    }
  }

  // ── Helpers ─────────────────────────────────────────────

  String _fmt(String? iso) {
    if (iso == null) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '—';
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Booking Details')),
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

    final b        = _booking!;
    final status   = b['status'] as String;
    final service  = b['services'] as Map?;
    final cat      = service?['service_categories'] as Map?;
    final client   = b['client']   as Map?;
    final provider = b['provider'] as Map?;
    final address  = b['address']  as String? ?? '';

    final arrivedAt   = b['provider_arrived_at']  as String?;
    final startedAt   = b['service_started_at']   as String?;
    final completedAt = b['service_completed_at'] as String?;

    final canMarkArrived  = _isProvider && status == 'confirmed' && arrivedAt == null;
    final canMarkStarted  = _isProvider && status == 'confirmed' && arrivedAt != null && startedAt == null;
    final canMarkComplete = _isProvider && status == 'confirmed' && startedAt != null;

    Color statusColor;
    switch (status) {
      case 'pending':   statusColor = Colors.orange; break;
      case 'confirmed': statusColor = Colors.green;  break;
      case 'completed': statusColor = Colors.blue;   break;
      default:          statusColor = Colors.grey;
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Status pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withOpacity(0.4)),
                ),
                child: Text(
                  status[0].toUpperCase() + status.substring(1),
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ),

            const SizedBox(height: 24),

            // Service info
            _Section(
              title: 'Service',
              child: Row(children: [
                Text(cat?['icon'] ?? '✂️', style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service?['service_name'] ?? '',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      Text('${cat?['name'] ?? ''} · ${service?['duration_minutes'] ?? ''} min'),
                    ],
                  ),
                ),
                Text('\$${service?['price'] ?? b['total_price']}',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Theme.of(context).colorScheme.primary)),
              ]),
            ),

            const SizedBox(height: 16),

            // People
            _Section(
              title: _isProvider ? 'Client' : 'Provider',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: _isProvider
                        ? (client?['full_name'] ?? '—')
                        : (provider?['full_name'] ?? '—'),
                  ),
                  if (_isProvider && client?['phone'] != null)
                    _InfoRow(icon: Icons.phone_outlined, label: client!['phone']),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Date & Address
            _Section(
              title: 'When & Where',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.calendar_month_outlined, label: _fmt(b['booking_time'])),
                  const SizedBox(height: 8),
                  _InfoRow(icon: Icons.location_on_outlined, label: address.isNotEmpty ? address : 'No address provided'),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openMaps(address),
                        icon: const Icon(Icons.navigation_outlined),
                        label: const Text('Open in Maps / Navigate'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          foregroundColor: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (b['client_note'] != null && (b['client_note'] as String).isNotEmpty) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'Client Note',
                child: Text(b['client_note'], style: const TextStyle(fontStyle: FontStyle.italic)),
              ),
            ],

            // Journey timeline
            if (arrivedAt != null || startedAt != null || completedAt != null) ...[
              const SizedBox(height: 16),
              _Section(
                title: 'Service Timeline',
                child: Column(
                  children: [
                    _TimelineRow(label: 'Provider Arrived', time: _fmt(arrivedAt), done: arrivedAt != null),
                    _TimelineRow(label: 'Service Started', time: _fmt(startedAt), done: startedAt != null),
                    _TimelineRow(label: 'Service Completed', time: _fmt(completedAt), done: completedAt != null),
                  ],
                ),
              ),
            ],

            // CHAT BUTTON
            if (status == 'confirmed' || status == 'completed') ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => context.push('/chat/${widget.bookingId}'),
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('Open Chat'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ],

            // LIVE TRACKING BUTTON
            if (status == 'confirmed') ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => context.push('/tracking/${widget.bookingId}'),
                icon: const Icon(Icons.my_location_rounded),
                label: const Text('Live Tracking'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ],

            // PAY NOW BUTTON (client only)
            if (!_isProvider && status == 'confirmed' && b['payment_status'] == 'unpaid') ...[
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () => context.push('/payment/${widget.bookingId}'),
                icon: const Icon(Icons.payment_rounded),
                label: const Text('Pay Now'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  minimumSize: const Size(double.infinity, 0),
                ),
              ),
            ],

            // REVIEW BUTTON (client only, after completed)
            if (!_isProvider && status == 'completed') ...[
              const SizedBox(height: 16),
              FutureBuilder(
                future: supabase
                    .from('reviews')
                    .select('id')
                    .eq('booking_id', widget.bookingId)
                    .maybeSingle(),
                builder: (context, snapshot) {
                  final hasReview = snapshot.data != null;
                  if (hasReview) {
                    return Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: Colors.green),
                          SizedBox(width: 8),
                          Text('You have reviewed this booking',
                              style: TextStyle(color: Colors.green)),
                        ],
                      ),
                    );
                  }
                  return ElevatedButton.icon(
                    onPressed: () => context.push('/review/${widget.bookingId}'),
                    icon: const Icon(Icons.star_rounded),
                    label: const Text('Leave a Review'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      minimumSize: const Size(double.infinity, 0),
                    ),
                  );
                },
              ),
            ],

            // Provider action buttons
            if (_isProvider && status == 'confirmed') ...[
              const SizedBox(height: 24),
              if (canMarkArrived)
                FilledButton.icon(
                  onPressed: _markArrived,
                  icon: const Icon(Icons.place_rounded),
                  label: const Text('Mark as Arrived'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Colors.blue),
                ),
              if (canMarkStarted)
                FilledButton.icon(
                  onPressed: _markStarted,
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Start Service'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: Colors.purple),
                ),
              if (canMarkComplete)
                FilledButton.icon(
                  onPressed: _markCompleted,
                  icon: const Icon(Icons.check_circle_outline),
                  label: const Text('Complete Service'),
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                ),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}

// ── Sub-widgets ─────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey),
      const SizedBox(width: 8),
      Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
    ]);
  }
}

class _TimelineRow extends StatelessWidget {
  final String label;
  final String time;
  final bool done;
  const _TimelineRow({required this.label, required this.time, required this.done});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Icon(done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: done ? Colors.green : Colors.grey, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: TextStyle(color: done ? Colors.black87 : Colors.grey,
            fontWeight: done ? FontWeight.w600 : FontWeight.normal))),
        Text(time, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ]),
    );
  }
}