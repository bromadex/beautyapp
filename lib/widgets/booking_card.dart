import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

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

    Color statusColor;
    switch (status) {
      case 'pending':
        statusColor = Colors.orange;
        break;
      case 'confirmed':
        statusColor = Colors.green;
        break;
      case 'completed':
        statusColor = Colors.blue;
        break;
      default:
        statusColor = Colors.grey;
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/booking/${booking['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Text(cat?['icon'] ?? '✂️',
                    style: const TextStyle(fontSize: 24)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(service?['service_name'] ?? 'Service',
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(
                        isClient
                            ? 'with ${profile?['full_name'] ?? 'Provider'}'
                            : 'Client: ${profile?['full_name'] ?? 'Client'}',
                        style: const TextStyle(
                            color: Colors.grey, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: statusColor.withOpacity(0.4)),
                      ),
                      child: Text(
                        status[0].toUpperCase() + status.substring(1),
                        style: TextStyle(
                            color: statusColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 12),
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: const BoxDecoration(
                          color: Colors.red,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$unreadCount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ],
                ),
              ]),

              const SizedBox(height: 10),
              Row(children: [
                const Icon(Icons.access_time_rounded,
                    size: 15, color: Colors.grey),
                const SizedBox(width: 4),
                Text(timeStr,
                    style: const TextStyle(
                        fontSize: 13, color: Colors.grey)),
              ]),
              const SizedBox(height: 4),
              Row(children: [
                const Icon(Icons.location_on_outlined,
                    size: 15, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(booking['address'] ?? '',
                      style: const TextStyle(
                          fontSize: 13, color: Colors.grey),
                      overflow: TextOverflow.ellipsis),
                ),
                Text('\$${booking['total_price']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 15)),
              ]),

              if (booking['client_note'] != null &&
                  (booking['client_note'] as String).isNotEmpty) ...[
                const SizedBox(height: 6),
                Text('Note: ${booking['client_note']}',
                    style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: Colors.grey)),
              ],

              // Action buttons
              if (onAccept != null || onDecline != null ||
                  onComplete != null || onCancel != null) ...[
                const SizedBox(height: 12),
                Row(children: [
                  if (onDecline != null) ...[
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onDecline,
                        style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red)),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  if (onAccept != null)
                    Expanded(
                      child: FilledButton(
                        onPressed: onAccept,
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.green),
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
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red)),
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
      return const Center(
        child: Text('Nothing here', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: bookings.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
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