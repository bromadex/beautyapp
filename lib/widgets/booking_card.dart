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

  const BookingCard({
    super.key,
    required this.booking,
    required this.isClient,
    this.unreadCount = 0,
    this.onAccept,
    this.onDecline,
    this.onComplete,
    this.onCancel,
  });

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

  const BookingList({
    super.key,
    required this.bookings,
    required this.isProvider,
    this.onAccept,
    this.onDecline,
    this.onComplete,
    this.onCancel,
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
        unreadCount: 0, // TODO: Fetch actual unread count per booking
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
      ),
    );
  }
}
