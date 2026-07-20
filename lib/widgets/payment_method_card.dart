import 'package:flutter/material.dart';

class PaymentMethodCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String value;
  final String? selectedValue;
  final ValueChanged<String> onTap;

  const PaymentMethodCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selectedValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = value == selectedValue;
    return GestureDetector(
      onTap: () => onTap(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.shade300,
            width: selected ? 2 : 1,
          ),
          color: selected
              ? Theme.of(context).colorScheme.primary.withOpacity(0.06)
              : Colors.white,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: selected
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.15)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon,
                  color: selected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade600),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: selected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.black87)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded,
                  color: Theme.of(context).colorScheme.primary),
          ],
        ),
      ),
    );
  }
}