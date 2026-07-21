import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';

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

  // -- Navigation --

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

  // -- Status updates (provider only) --

  Future<void> _markArrived() async {
    await supabase.from('bookings').update({
      'provider_arrived_at': DateTime.now().toIso8601String(),
    }).eq('id', widget.bookingId);
    final providerName = _booking?['provider']?['full_name'] ?? 'Your stylist';
    NotificationService.send(
      userId: _booking!['client_id'],
      type: 'booking_status',
      title: 'Stylist Arrived',
      body: '$providerName has arrived at your location',
      referenceId: widget.bookingId,
    );
    _load();
  }

  Future<void> _markStarted() async {
    await supabase.from('bookings').update({
      'service_started_at': DateTime.now().toIso8601String(),
      'status':             'confirmed',
    }).eq('id', widget.bookingId);
    final providerName = _booking?['provider']?['full_name'] ?? 'Your stylist';
    NotificationService.send(
      userId: _booking!['client_id'],
      type: 'booking_status',
      title: 'Service Started',
      body: '$providerName has started your service',
      referenceId: widget.bookingId,
    );
    _load();
  }

  Future<void> _markCompleted() async {
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
      final providerName = _booking?['provider']?['full_name'] ?? 'Your stylist';
      final serviceName = _booking?['services']?['service_name'] ?? 'your service';
      NotificationService.send(
        userId: _booking!['client_id'],
        type: 'booking_status',
        title: 'Service Completed',
        body: '$providerName completed $serviceName. Leave a review!',
        referenceId: widget.bookingId,
      );
      _load();
    }
  }

  // -- Helpers --

  String _fmt(String? iso) {
    if (iso == null) return '--';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return '--';
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

    final statusFg = StatusColors.foreground(status);
    final statusBg = StatusColors.background(status);

    return Scaffold(
      appBar: AppBar(title: const Text('Booking Details')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // Status pill
            Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: AppRadius.xxlAll,
                  border: Border.all(color: statusFg.withValues(alpha: 0.3)),
                ),
                child: Text(
                  StatusColors.label(status),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: statusFg,
                      ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Service info section
            _Section(
              title: 'SERVICE',
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: AppRadius.mdAll,
                  ),
                  alignment: Alignment.center,
                  child: Text(cat?['icon'] ?? '', style: const TextStyle(fontSize: 24)),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service?['service_name'] ?? '',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${cat?['name'] ?? ''} -- ${service?['duration_minutes'] ?? ''} min',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text('\$${service?['price'] ?? b['total_price']}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(color: AppColors.primary)),
              ]),
            ),

            const SizedBox(height: AppSpacing.md),

            // People section
            _Section(
              title: _isProvider ? 'CLIENT' : 'PROVIDER',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(
                    icon: Icons.person_outline,
                    label: _isProvider
                        ? (client?['full_name'] ?? '--')
                        : (provider?['full_name'] ?? '--'),
                  ),
                  if (_isProvider && client?['phone'] != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(icon: Icons.phone_outlined, label: client!['phone']),
                  ],
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.md),

            // When & Where section
            _Section(
              title: 'WHEN & WHERE',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _InfoRow(icon: Icons.calendar_month_outlined, label: _fmt(b['booking_time'])),
                  const SizedBox(height: AppSpacing.sm),
                  _InfoRow(icon: Icons.location_on_outlined, label: address.isNotEmpty ? address : 'No address provided'),
                  if (address.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openMaps(address),
                        icon: const Icon(Icons.navigation_outlined, size: 18),
                        label: const Text('Open in Maps'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Client note
            if (b['client_note'] != null && (b['client_note'] as String).isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'CLIENT NOTE',
                child: Text(b['client_note'],
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(fontStyle: FontStyle.italic)),
              ),
            ],

            // Service timeline
            if (arrivedAt != null || startedAt != null || completedAt != null) ...[
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: 'SERVICE TIMELINE',
                child: _ServiceTimeline(
                  arrivedAt: arrivedAt,
                  startedAt: startedAt,
                  completedAt: completedAt,
                  fmt: _fmt,
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),

            // Action cards: Chat, Track, Pay
            if (status == 'confirmed' || status == 'completed') ...[
              _ActionCard(
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Open Chat',
                subtitle: 'Message about this booking',
                color: AppColors.info,
                onTap: () => context.push('/chat/${widget.bookingId}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (status == 'confirmed') ...[
              _ActionCard(
                icon: Icons.my_location_rounded,
                label: 'Live Tracking',
                subtitle: 'Track provider location in real time',
                color: AppColors.success,
                onTap: () => context.push('/tracking/${widget.bookingId}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (!_isProvider && status == 'confirmed' && b['payment_status'] == 'unpaid') ...[
              _ActionCard(
                icon: Icons.payment_rounded,
                label: 'Pay Now',
                subtitle: 'Complete payment for this service',
                color: AppColors.primary,
                onTap: () => context.push('/payment/${widget.bookingId}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            // Review section (client only, after completed)
            if (!_isProvider && status == 'completed') ...[
              const SizedBox(height: AppSpacing.sm),
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
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.08),
                        borderRadius: AppRadius.lgAll,
                        border: Border.all(
                            color: AppColors.success.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: AppColors.success, size: 22),
                          const SizedBox(width: AppSpacing.sm),
                          Text('You have reviewed this booking',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(color: AppColors.success)),
                        ],
                      ),
                    );
                  }
                  return _ActionCard(
                    icon: Icons.star_rounded,
                    label: 'Leave a Review',
                    subtitle: 'Rate your experience with this service',
                    color: AppColors.warning,
                    onTap: () => context.push('/review/${widget.bookingId}'),
                  );
                },
              ),
            ],

            // Provider action buttons
            if (_isProvider && status == 'confirmed') ...[
              const SizedBox(height: AppSpacing.xxl),
              if (canMarkArrived)
                _ProviderActionButton(
                  icon: Icons.place_rounded,
                  label: 'Mark as Arrived',
                  color: AppColors.info,
                  onPressed: _markArrived,
                ),
              if (canMarkStarted)
                _ProviderActionButton(
                  icon: Icons.play_circle_outline,
                  label: 'Start Service',
                  color: AppColors.secondary,
                  onPressed: _markStarted,
                ),
              if (canMarkComplete)
                _ProviderActionButton(
                  icon: Icons.check_circle_outline,
                  label: 'Complete Service',
                  color: AppColors.success,
                  onPressed: _markCompleted,
                ),
            ],

            const SizedBox(height: AppSpacing.xxxl + AppSpacing.sm),
          ],
        ),
      ),
    );
  }
}

// -- Sub-widgets --

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(letterSpacing: 0.8)),
          const SizedBox(height: AppSpacing.md),
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
      Icon(icon, size: 18, color: AppColors.textTertiary),
      const SizedBox(width: AppSpacing.sm),
      Expanded(
        child: Text(label, style: Theme.of(context).textTheme.bodyLarge),
      ),
    ]);
  }
}

class _ServiceTimeline extends StatelessWidget {
  final String? arrivedAt;
  final String? startedAt;
  final String? completedAt;
  final String Function(String?) fmt;

  const _ServiceTimeline({
    required this.arrivedAt,
    required this.startedAt,
    required this.completedAt,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final steps = [
      _TimelineStep('Provider Arrived', fmt(arrivedAt), arrivedAt != null),
      _TimelineStep('Service Started', fmt(startedAt), startedAt != null),
      _TimelineStep('Service Completed', fmt(completedAt), completedAt != null),
    ];

    return Column(
      children: List.generate(steps.length, (i) {
        final step = steps[i];
        final isLast = i == steps.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dot + connecting line
              SizedBox(
                width: 24,
                child: Column(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      margin: const EdgeInsets.only(top: 3),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: step.done
                            ? AppColors.success
                            : Colors.grey.shade300,
                        border: step.done
                            ? Border.all(
                                color: AppColors.success.withValues(alpha: 0.3),
                                width: 3)
                            : null,
                      ),
                      child: step.done
                          ? const Icon(Icons.check,
                              size: 8, color: Colors.white)
                          : null,
                    ),
                    if (!isLast)
                      Expanded(
                        child: Container(
                          width: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          color: step.done
                              ? AppColors.success.withValues(alpha: 0.3)
                              : Colors.grey.shade200,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              // Label + time
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                      bottom: isLast ? 0 : AppSpacing.lg),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        step.label,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: step.done
                                  ? AppColors.textPrimary
                                  : AppColors.textTertiary,
                              fontWeight: step.done
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                      ),
                      Text(step.time,
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _TimelineStep {
  final String label;
  final String time;
  final bool done;
  const _TimelineStep(this.label, this.time, this.done);
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cardLight,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded,
                  color: AppColors.textTertiary, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProviderActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ProviderActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: SizedBox(
        width: double.infinity,
        child: FilledButton.icon(
          onPressed: onPressed,
          icon: Icon(icon),
          label: Text(label),
          style: FilledButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
        ),
      ),
    );
  }
}
