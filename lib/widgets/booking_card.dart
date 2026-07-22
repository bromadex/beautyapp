import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../theme.dart';

class BookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final bool isClient;
  final int unreadCount;
  final VoidCallback? onAccept;
  final VoidCallback? onDecline;
  final VoidCallback? onComplete;
  final VoidCallback? onCancel;
  final void Function(String bookingId, double counterPrice)? onCounterOffer;
  final void Function(String bookingId)? onAcceptOffer;
  final void Function(String bookingId)? onDeclineOffer;

  const BookingCard({
    super.key,
    required this.booking,
    required this.isClient,
    this.unreadCount = 0,
    this.onAccept,
    this.onDecline,
    this.onComplete,
    this.onCancel,
    this.onCounterOffer,
    this.onAcceptOffer,
    this.onDeclineOffer,
  });

  bool get _hasNegotiation {
    final ns = booking['negotiation_status'] ?? 'none';
    return ns != 'none';
  }

  Widget _buildNegotiationBanner(BuildContext context) {
    final ns = booking['negotiation_status'] ?? 'none';
    final offeredPrice = (booking['client_offered_price'] as num?)?.toDouble();
    final counterPrice = (booking['provider_counter_price'] as num?)?.toDouble();
    final agreedPrice = (booking['agreed_price'] as num?)?.toDouble();
    final expiresAt = DateTime.tryParse(booking['offer_expires_at'] ?? '');
    final isExpired = expiresAt != null && expiresAt.isBefore(DateTime.now());

    Color bannerColor;
    IconData bannerIcon;
    String bannerTitle;
    String bannerSubtitle;

    switch (ns) {
      case 'client_offered':
        bannerColor = AppColors.info;
        bannerIcon = Icons.local_offer_rounded;
        bannerTitle = isClient
            ? 'Your offer: \$${offeredPrice?.toStringAsFixed(0)}'
            : 'Price offer: \$${offeredPrice?.toStringAsFixed(0)}';
        bannerSubtitle = isExpired
            ? 'Offer expired'
            : isClient
                ? 'Waiting for provider response'
                : 'Listed: \$${booking['total_price']}';
        break;
      case 'provider_countered':
        bannerColor = AppColors.warning;
        bannerIcon = Icons.swap_horiz_rounded;
        bannerTitle = isClient
            ? 'Counter-offer: \$${counterPrice?.toStringAsFixed(0)}'
            : 'You countered: \$${counterPrice?.toStringAsFixed(0)}';
        bannerSubtitle = isClient
            ? 'You offered \$${offeredPrice?.toStringAsFixed(0)}'
            : 'Client offered \$${offeredPrice?.toStringAsFixed(0)}';
        break;
      case 'agreed':
        bannerColor = AppColors.success;
        bannerIcon = Icons.handshake_rounded;
        bannerTitle = 'Agreed: \$${agreedPrice?.toStringAsFixed(0)}';
        bannerSubtitle = 'Price accepted by both parties';
        break;
      case 'declined':
        bannerColor = AppColors.error;
        bannerIcon = Icons.block_rounded;
        bannerTitle = 'Offer declined';
        bannerSubtitle = 'Client offered \$${offeredPrice?.toStringAsFixed(0)}';
        break;
      default:
        return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: bannerColor.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: bannerColor.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(bannerIcon, size: 18, color: bannerColor),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(bannerTitle,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: bannerColor,
                        )),
                    Text(bannerSubtitle,
                        style: TextStyle(
                          fontSize: 11,
                          color: bannerColor.withValues(alpha: 0.8),
                        )),
                  ],
                ),
              ),
              if (expiresAt != null && !isExpired && ns != 'agreed' && ns != 'declined')
                Text(
                  _timeRemaining(expiresAt),
                  style: TextStyle(fontSize: 10, color: bannerColor),
                ),
            ],
          ),
          // Provider action buttons for client_offered
          if (!isClient && ns == 'client_offered' && !isExpired) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onDeclineOffer?.call(booking['id']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Decline', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => _showCounterDialog(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.warning,
                      side: const BorderSide(color: AppColors.warning),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Counter', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAcceptOffer?.call(booking['id']),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      'Accept \$${offeredPrice?.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // Client action buttons for provider_countered
          if (isClient && ns == 'provider_countered' && !isExpired) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => onDeclineOffer?.call(booking['id']),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.error,
                      side: const BorderSide(color: AppColors.error),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Decline', style: TextStyle(fontSize: 12)),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: FilledButton(
                    onPressed: () => onAcceptOffer?.call(booking['id']),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(
                      'Accept \$${counterPrice?.toStringAsFixed(0)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showCounterDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Counter Offer'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            prefixText: '\$ ',
            hintText: 'Your price',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final price = double.tryParse(ctrl.text.trim());
              if (price != null && price > 0) {
                Navigator.pop(ctx);
                onCounterOffer?.call(booking['id'], price);
              }
            },
            child: const Text('Send Counter'),
          ),
        ],
      ),
    );
  }

  String _timeRemaining(DateTime expiresAt) {
    final diff = expiresAt.difference(DateTime.now());
    if (diff.inHours > 0) return '${diff.inHours}h left';
    if (diff.inMinutes > 0) return '${diff.inMinutes}m left';
    return 'Expiring';
  }

  @override
  Widget build(BuildContext context) {
    final status = booking['status'] as String;
    final service = booking['services'] as Map?;
    final cat = service?['service_categories'] as Map?;
    final profile = booking['profiles'] as Map?;
    final bookingTime = DateTime.tryParse(booking['booking_time'] ?? '');
    final timeStr = bookingTime != null
        ? '${bookingTime.day}/${bookingTime.month}/${bookingTime.year} at ${TimeOfDay.fromDateTime(bookingTime).format(context)}'
        : 'Unknown time';

    final statusBg = StatusColors.background(status);
    final statusFg = StatusColors.foreground(status);
    final statusLabel = StatusColors.label(status);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: () => context.push('/booking/${booking['id']}'),
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // -- Header row: icon, service/provider, status chip, unread --
              Row(children: [
                Text(cat?['icon'] ?? '✂️',
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service?['service_name'] ?? 'Service',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        isClient
                            ? 'with ${profile?['full_name'] ?? 'Provider'}'
                            : 'Client: ${profile?['full_name'] ?? 'Client'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: statusBg,
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(
                            color: statusFg.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        statusLabel,
                        style: TextStyle(
                          color: statusFg,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ]),

              const SizedBox(height: AppSpacing.md),

              // -- Date/time row --
              Row(children: [
                Icon(Icons.access_time_rounded,
                    size: 15, color: AppColors.textTertiary),
                const SizedBox(width: AppSpacing.xs),
                Text(timeStr, style: Theme.of(context).textTheme.bodySmall),
              ]),

              const SizedBox(height: AppSpacing.xs),

              // -- Address & price row --
              Row(children: [
                Icon(Icons.location_on_outlined,
                    size: 15, color: AppColors.textTertiary),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    booking['address'] ?? '',
                    style: Theme.of(context).textTheme.bodySmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '\$${booking['total_price']}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ]),

              // -- Client note --
              if (booking['client_note'] != null &&
                  (booking['client_note'] as String).isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Note: ${booking['client_note']}',
                  style: Theme.of(context).textTheme.bodySmall!.copyWith(
                        fontStyle: FontStyle.italic,
                      ),
                ),
              ],

              // -- Price negotiation banner --
              if (_hasNegotiation) ...[
                const SizedBox(height: AppSpacing.sm),
                _buildNegotiationBanner(context),
              ],

              // -- Action buttons --
              if (onAccept != null ||
                  onDecline != null ||
                  onComplete != null ||
                  onCancel != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(children: [
                  if (onDecline != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDecline,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                  ],
                  if (onAccept != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onAccept,
                        style: FilledButton.styleFrom(
                            backgroundColor: AppColors.success),
                        child: const Text('Accept'),
                      ),
                    ),
                  if (onComplete != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onComplete,
                        child: const Text('Mark Completed'),
                      ),
                    ),
                  if (onCancel != null)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: const BorderSide(color: AppColors.error),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class BookingList extends StatelessWidget {
  final List<Map<String, dynamic>> bookings;
  final bool isProvider;
  final void Function(String)? onAccept;
  final void Function(String)? onDecline;
  final void Function(String)? onComplete;
  final void Function(String)? onCancel;
  final void Function(String bookingId, double counterPrice)? onCounterOffer;
  final void Function(String bookingId)? onAcceptOffer;
  final void Function(String bookingId)? onDeclineOffer;

  const BookingList({
    super.key,
    required this.bookings,
    required this.isProvider,
    this.onAccept,
    this.onDecline,
    this.onComplete,
    this.onCancel,
    this.onCounterOffer,
    this.onAcceptOffer,
    this.onDeclineOffer,
  });

  @override
  Widget build(BuildContext context) {
    if (bookings.isEmpty) {
      return Center(
        child: Text(
          'Nothing here',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      );
    }
    return ListView.separated(
      padding: AppSpacing.screenPadding,
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => BookingCard(
        booking: bookings[i],
        isClient: !isProvider,
        unreadCount: 0,
        onAccept: onAccept != null
            ? () => onAccept!(bookings[i]['id'])
            : null,
        onDecline: onDecline != null
            ? () => onDecline!(bookings[i]['id'])
            : null,
        onComplete: onComplete != null
            ? () => onComplete!(bookings[i]['id'])
            : null,
        onCancel: onCancel != null
            ? () => onCancel!(bookings[i]['id'])
            : null,
        onCounterOffer: onCounterOffer,
        onAcceptOffer: onAcceptOffer,
        onDeclineOffer: onDeclineOffer,
      ),
    );
  }
}
