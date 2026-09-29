import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../services/paynow_service.dart';
import '../widgets/reschedule_sheet.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart';

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
  Map<String, dynamic>? _policy;
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
            service_tiers(name, duration_minutes),
            booking_addons(addon_name, addon_price, addon_duration),
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

      final policy = await supabase
          .from('cancellation_policies')
          .select()
          .eq('provider_id', data['provider_id'])
          .maybeSingle();

      fillWalkin(data, 'client');
      if (mounted) {
        setState(() {
          _booking    = data;
          _policy     = policy;
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
      'provider_arrived_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', widget.bookingId);
    final providerName = _booking?['provider']?['full_name'] ?? 'Your pro';
    NotificationService.send(
      userId: _booking!['client_id'],
      type: 'booking_status',
      title: 'Your pro has arrived',
      body: '$providerName has arrived at your location',
      referenceId: widget.bookingId,
    );
    _load();
  }

  Future<void> _markStarted() async {
    await supabase.from('bookings').update({
      'service_started_at': DateTime.now().toUtc().toIso8601String(),
      'status':             'confirmed',
    }).eq('id', widget.bookingId);
    final providerName = _booking?['provider']?['full_name'] ?? 'Your pro';
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
          child: const Icon(TablerIcons.circle_check,
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
        'service_completed_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.bookingId);
      final providerName = _booking?['provider']?['full_name'] ?? 'Your pro';
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

  // -- Cancel booking --
  double get _lateCancelFee {
    final b = _booking!;
    if (_isProvider || b['status'] != 'confirmed' || _policy == null) return 0;
    final start = DateTime.tryParse(b['booking_time'] ?? '');
    if (start == null) return 0;
    final freeHours = (_policy!['free_cancel_hours'] as num?)?.toInt() ?? 24;
    if (start.difference(DateTime.now()).inMinutes >= freeHours * 60) return 0;
    final pct = (_policy!['late_cancel_fee_percent'] as num?)?.toDouble() ?? 0;
    final total = (b['total_price'] as num?)?.toDouble() ?? 0;
    return (total * pct / 100 * 100).roundToDouble() / 100;
  }

  Future<void> _cancelBooking() async {
    final fee = _lateCancelFee;
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Cancel Booking'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Are you sure you want to cancel this booking?'),
              if (fee > 0) ...[
                const SizedBox(height: AppSpacing.md),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    'This is within ${_policy!['free_cancel_hours']}h of your appointment, '
                    'so a late cancellation fee of \$${fee.toStringAsFixed(2)} applies.',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: 'Reason (optional)',
                  border: OutlineInputBorder(),
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Keep Booking')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Cancel Booking'),
            ),
          ],
        );
      },
    );
    if (reason == null) return;

    try {
      await supabase.rpc('cancel_booking', params: {
        'p_booking_id': widget.bookingId,
        'p_reason': reason,
      });
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  // -- No-show --
  Future<void> _markNoShow() async {
    final other = _isProvider ? 'the client' : 'your pro';
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Report a No-Show?'),
        content: Text(
            'Only do this if $other did not turn up. The booking will be closed'
            '${_isProvider && _policy != null ? ' and your no-show fee of ${_policy!['no_show_fee_percent']}% will be recorded' : ''}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Report No-Show'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await supabase.rpc('mark_no_show', params: {'p_booking_id': widget.bookingId});
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _payDeposit() async {
    final b = _booking!;
    final phoneCtrl = TextEditingController(text: (b['client']?['phone'] ?? '').toString());
    final method = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Pay deposit', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 12),
          TextField(
            controller: phoneCtrl,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'EcoCash number', prefixIcon: Icon(TablerIcons.device_mobile)),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'ecocash'), child: const Text('Pay with EcoCash')),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: () => Navigator.pop(ctx, 'web'), child: const Text('Pay by card')),
        ]),
      ),
    );
    if (method == null || !mounted) return;
    final outcome = await PaynowCheckout.run(
      context,
      purpose: 'deposit',
      bookingId: widget.bookingId,
      method: method,
      phone: method == 'ecocash' ? phoneCtrl.text.trim() : null,
    );
    if (outcome == PaynowOutcome.paid && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Deposit paid — thank you!')));
      _load();
    }
  }

  // -- Book Again --
  void _bookAgain() {
    final b = _booking!;
    context.push('/book/${b['provider_id']}/${b['service_id']}');
  }

  // -- Report Issue --
  void _reportIssue() {
    context.push('/dispute/${widget.bookingId}');
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
                  child: const Icon(TablerIcons.alert_circle,
                      size: 48, color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.lg),
                Text(_error!,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(TablerIcons.refresh),
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
    final hideStudio = !_isProvider && b['at_studio'] == true && status == 'pending';
    final address  = hideStudio
        ? 'At the pro\'s studio. The address shows once the pro confirms.'
        : b['at_studio'] == true
            ? 'Studio: ${b['address'] ?? ''}'
            : (b['address'] as String? ?? '');

    final arrivedAt   = b['provider_arrived_at']  as String?;
    final startedAt   = b['service_started_at']   as String?;
    final completedAt = b['service_completed_at'] as String?;

    final canMarkArrived  = _isProvider && status == 'confirmed' && arrivedAt == null && !isManualBooking(b);
    final canMarkStarted  = _isProvider && status == 'confirmed' && arrivedAt != null && startedAt == null;
    final isManual = isManualBooking(b);
    final canMarkComplete = _isProvider && status == 'confirmed' && (startedAt != null || isManual);

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
                  child: Icon(categoryIcon(cat?['name']), size: 24, color: AppColors.primary),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service?['service_name'] ?? '',
                          style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xs),
                      Text('${cat?['name'] ?? ''} · ${service?['duration_minutes'] ?? ''} min',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
                Text('\$${b['total_price'] ?? service?['price']}',
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
                    icon: TablerIcons.user,
                    label: _isProvider
                        ? (client?['full_name'] ?? '--')
                        : (provider?['full_name'] ?? '--'),
                  ),
                  if (_isProvider && client?['phone'] != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(icon: TablerIcons.phone, label: client!['phone']),
                  ],
                  if (_isProvider && isManual) ...[
                    const SizedBox(height: AppSpacing.sm),
                    const _InfoRow(icon: TablerIcons.notes, label: 'Added by you (not booked in the app)'),
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
                  _InfoRow(icon: TablerIcons.calendar_month, label: _fmt(b['booking_time'])),
                  if (b['ref'] != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _InfoRow(icon: TablerIcons.ticket, label: 'Reference #${b['ref']}'),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  _InfoRow(icon: TablerIcons.map_pin, label: address.isNotEmpty ? address : 'No address provided'),
                  if (address.isNotEmpty && address != 'At the salon' && !hideStudio) ...[
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _openMaps((b['address'] ?? address).toString()),
                        icon: const Icon(TablerIcons.navigation, size: 18),
                        label: const Text('Open in Maps'),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            if (((b['cancellation_fee'] as num?) ?? 0) > 0) ...[
              const SizedBox(height: AppSpacing.md),
              _Section(
                title: b['no_show_by'] != null ? 'NO-SHOW FEE' : 'CANCELLATION FEE',
                child: _InfoRow(
                  icon: TablerIcons.receipt,
                  label: '\$${(b['cancellation_fee'] as num).toStringAsFixed(2)} owed to the pro'
                      '${b['cancel_reason'] != null ? ' — ${b['cancel_reason']}' : ''}',
                ),
              ),
            ],

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

            // Action cards
            if (!_isProvider &&
                (status == 'pending' || status == 'confirmed') &&
                ((b['deposit_amount'] as num?) ?? 0) > 0 &&
                b['deposit_paid'] != true) ...[
              _ActionCard(
                icon: TablerIcons.lock_cog,
                label: 'Pay \$${(b['deposit_amount'] as num).toStringAsFixed(2)} deposit',
                subtitle: 'Secure your slot with EcoCash or card',
                color: AppColors.primary,
                onTap: _payDeposit,
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (status == 'pending' || status == 'confirmed') ...[
              _ActionCard(
                icon: TablerIcons.calendar_cog,
                label: 'Reschedule',
                subtitle: _isProvider ? 'Move to another time' : 'Pick another free time',
                color: AppColors.info,
                onTap: () async {
                  if (await showRescheduleSheet(context, b)) _load();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (status == 'completed' || (_isProvider && isManual && status == 'confirmed')) ...[
              _ActionCard(
                icon: TablerIcons.receipt,
                label: 'Share receipt',
                subtitle: 'Send it on WhatsApp',
                color: const Color(0xFF25D366),
                onTap: () => shareOnWhatsApp(
                  receiptText(b,
                      stylist: provider?['full_name'] ?? 'Your pro',
                      client: client?['full_name'] ?? 'Client'),
                  phone: _isProvider ? (client?['phone'] as String?) : null,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (_isProvider && b['payment_status'] != 'paid' && (status == 'confirmed' || status == 'completed')) ...[
              _ActionCard(
                icon: TablerIcons.cash,
                label: 'Mark as paid',
                subtitle: 'The client paid you in cash or EcoCash',
                color: AppColors.success,
                onTap: () async {
                  await supabase.from('bookings').update({'payment_status': 'paid'}).eq('id', widget.bookingId);
                  _load();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (!isManual && (status == 'pending' || status == 'confirmed' || status == 'completed')) ...[
              _ActionCard(
                icon: TablerIcons.message_circle,
                label: 'Open Chat',
                subtitle: 'Message about this booking',
                color: AppColors.info,
                onTap: () => context.push('/chat/${widget.bookingId}'),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],

            if (!_isProvider && status == 'confirmed' && b['payment_status'] == 'unpaid') ...[
              _ActionCard(
                icon: TablerIcons.credit_card,
                label: 'Pay online',
                subtitle: 'Pay the balance with EcoCash or card',
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
                          const Icon(TablerIcons.circle_check_filled,
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
                    icon: TablerIcons.star_filled,
                    label: 'Leave a Review',
                    subtitle: 'Rate your experience with this service',
                    color: AppColors.warning,
                    onTap: () => context.push('/review/${widget.bookingId}'),
                  );
                },
              ),
            ],

            // WhatsApp contact button
            if (status == 'confirmed') ...[
              const SizedBox(height: AppSpacing.sm),
              FutureBuilder(
                future: _isProvider
                    ? supabase
                        .from('profiles')
                        .select('whatsapp_number')
                        .eq('id', b['client_id'])
                        .maybeSingle()
                    : supabase
                        .from('profiles')
                        .select('whatsapp_number')
                        .eq('id', b['provider_id'])
                        .maybeSingle(),
                builder: (context, snapshot) {
                  final whatsapp =
                      snapshot.data?['whatsapp_number'] as String?;
                  if (whatsapp == null || whatsapp.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return _ActionCard(
                    icon: TablerIcons.message_circle,
                    label: 'WhatsApp',
                    subtitle: 'Message on WhatsApp',
                    color: const Color(0xFF25D366),
                    onTap: () {
                      final clean =
                          whatsapp.replaceAll(RegExp(r'[^0-9+]'), '');
                      final uri =
                          Uri.parse('https://wa.me/$clean');
                      launchUrl(uri,
                          mode: LaunchMode.externalApplication);
                    },
                  );
                },
              ),
            ],

            // Client record (provider only)
            if (_isProvider) ...[
              const SizedBox(height: AppSpacing.sm),
              _ActionCard(
                icon: TablerIcons.user_search,
                label: 'Client record',
                subtitle: 'Visits, spend, notes and tags',
                color: AppColors.secondary,
                onTap: () => context.push(
                    '/provider/clients/${Uri.encodeComponent(clientKeyOf(b))}'),
              ),
            ],

            // Cancel booking (both client and provider, before completion)
            if (status == 'pending' || status == 'confirmed') ...[
              const SizedBox(height: AppSpacing.sm),
              _ActionCard(
                icon: TablerIcons.circle_x,
                label: 'Cancel Booking',
                subtitle: 'Cancel this appointment',
                color: AppColors.error,
                onTap: _cancelBooking,
              ),
            ],

            // Book Again (client only, after completed)
            if (!_isProvider && status == 'completed') ...[
              const SizedBox(height: AppSpacing.sm),
              _ActionCard(
                icon: TablerIcons.repeat,
                label: 'Book Again',
                subtitle: 'Rebook with the same provider and service',
                color: AppColors.secondary,
                onTap: _bookAgain,
              ),
            ],

            // No-show (either side, once the booking time has passed)
            if (status == 'confirmed' &&
                (DateTime.tryParse(b['booking_time'] ?? '')?.isBefore(DateTime.now()) ?? false)) ...[
              const SizedBox(height: AppSpacing.sm),
              _ActionCard(
                icon: TablerIcons.user_off,
                label: 'Report a No-Show',
                subtitle: _isProvider ? 'The client did not turn up' : 'Your pro did not arrive',
                color: AppColors.error,
                onTap: _markNoShow,
              ),
            ],

            // Report Issue (both sides, after confirmed or completed)
            if (!isManual && (status == 'confirmed' || status == 'completed')) ...[
              const SizedBox(height: AppSpacing.sm),
              _ActionCard(
                icon: TablerIcons.flag,
                label: 'Report an Issue',
                subtitle: 'Report a problem with this booking',
                color: AppColors.warning,
                onTap: _reportIssue,
              ),
            ],

            // Provider action buttons
            if (_isProvider && status == 'confirmed') ...[
              const SizedBox(height: AppSpacing.xxl),
              if (canMarkArrived)
                _ProviderActionButton(
                  icon: TablerIcons.map_pin,
                  label: 'Mark as Arrived',
                  color: AppColors.info,
                  onPressed: _markArrived,
                ),
              if (canMarkStarted)
                _ProviderActionButton(
                  icon: TablerIcons.player_play,
                  label: 'Start Service',
                  color: AppColors.secondary,
                  onPressed: _markStarted,
                ),
              if (canMarkComplete)
                _ProviderActionButton(
                  icon: TablerIcons.circle_check,
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
        border: Border.all(color: AppColors.border),
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
                            : AppColors.borderStrong,
                        border: step.done
                            ? Border.all(
                                color: AppColors.success.withValues(alpha: 0.3),
                                width: 3)
                            : null,
                      ),
                      child: step.done
                          ? const Icon(TablerIcons.check,
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
                              : AppColors.border,
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
            border: Border.all(color: AppColors.border),
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
              Icon(TablerIcons.chevron_right,
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
