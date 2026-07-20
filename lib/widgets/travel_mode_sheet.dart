import 'package:flutter/material.dart';

class TravelModeSheet extends StatelessWidget {
  final bool isProvider;
  const TravelModeSheet({super.key, required this.isProvider});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Who is travelling?',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text(
                'Select the arrangement you agreed on with the other party.'),
            const SizedBox(height: 24),
            _ModeButton(
              icon: Icons.directions_walk_rounded,
              title: 'Provider goes to Client',
              subtitle: 'The stylist travels to the client\'s location',
              value: 'provider_to_client',
            ),
            const SizedBox(height: 12),
            _ModeButton(
              icon: Icons.store_rounded,
              title: 'Client goes to Provider',
              subtitle: 'The client travels to the salon / provider\'s place',
              value: 'client_to_provider',
            ),
            const SizedBox(height: 12),
            _ModeButton(
              icon: Icons.location_on_rounded,
              title: 'Fixed Location (Salon)',
              subtitle: 'Provider has a fixed address — no live tracking needed',
              value: 'fixed_location',
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final String value;

  const _ModeButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => Navigator.pop(context, value),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.all(16),
        alignment: Alignment.centerLeft,
      ),
      child: Row(
        children: [
          Icon(icon, size: 28),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15)),
                Text(subtitle,
                    style: const TextStyle(
                        fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}