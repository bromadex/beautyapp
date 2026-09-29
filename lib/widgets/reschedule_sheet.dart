import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import 'slot_picker.dart';

/// Minutes a booking occupies: tier (or service) duration plus add-ons.
int bookingMinutes(Map<String, dynamic> b) {
  final base = (b['service_tiers']?['duration_minutes'] ?? b['services']?['duration_minutes'] ?? 60) as num;
  final extras = (b['booking_addons'] as List? ?? [])
      .fold<num>(0, (s, a) => s + ((a['addon_duration'] as num?) ?? 0));
  return (base + extras).toInt();
}

/// Lets either party move a booking to another free slot. Returns true if moved.
Future<bool> showRescheduleSheet(BuildContext context, Map<String, dynamic> booking) async {
  final moved = await showModalBottomSheet<bool>(
      useRootNavigator: true,
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _RescheduleSheet(booking: booking),
  );
  return moved == true;
}

class _RescheduleSheet extends StatefulWidget {
  final Map<String, dynamic> booking;
  const _RescheduleSheet({required this.booking});
  @override
  State<_RescheduleSheet> createState() => _RescheduleSheetState();
}

class _RescheduleSheetState extends State<_RescheduleSheet> {
  DateTime? _day;
  String? _time;
  bool _saving = false;

  Future<void> _save() async {
    if (_day == null || _time == null) return;
    setState(() => _saving = true);
    try {
      await supabase.rpc('reschedule_booking', params: {
        'p_booking_id': widget.booking['id'],
        'p_new_time': slotToDateTime(_day!, _time!).toIso8601String(),
      });
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isClient = widget.booking['client_id'] == supabase.auth.currentUser?.id;
    // Times scroll; the button stays at the bottom so it is always reachable.
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Move booking', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                isClient
                    ? 'Pick a new free time. Your pro will be asked to confirm it.'
                    : 'Pick a new time. Your client will be notified.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SlotPicker(
                providerId: widget.booking['provider_id'],
                minutes: bookingMinutes(widget.booking),
                onChanged: (d, t) => setState(() {
                  _day = d;
                  _time = t;
                }),
              ),
            ]),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(20, 10, 20, 16 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(border: Border(top: BorderSide(color: AppColors.border))),
          child: FilledButton(
            onPressed: _time == null || _saving ? null : _save,
            child: Text(_saving ? 'Moving…' : 'Move to this time'),
          ),
        ),
      ]),
    );
  }
}
