import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class DisputeScreen extends StatefulWidget {
  final String bookingId;
  const DisputeScreen({super.key, required this.bookingId});

  @override
  State<DisputeScreen> createState() => _DisputeScreenState();
}

class _DisputeScreenState extends State<DisputeScreen> {
  final _descCtrl = TextEditingController();
  String _category = 'service_problem';
  bool _submitting = false;
  Map<String, dynamic>? _booking;
  bool _loading = true;

  final _categories = {
    'service_problem': 'Service Problem',
    'payment_issue': 'Payment Issue',
    'no_show': 'No-Show',
    'misconduct': 'Misconduct',
    'other': 'Other',
  };

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final b = await supabase
          .from('bookings')
          .select('*, services(service_name), client:profiles!bookings_client_id_fkey(full_name), provider:profiles!bookings_provider_id_fkey(full_name)')
          .eq('id', widget.bookingId)
          .maybeSingle();
      if (mounted) setState(() { _booking = b; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submit() async {
    if (_descCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please describe the issue')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final isProvider = _booking?['provider_id'] == uid;
      final reportedUserId =
          isProvider ? (_booking?['client_id']) : (_booking?['provider_id']);

      await supabase.from('disputes').insert({
        'booking_id': widget.bookingId,
        'reporter_id': uid,
        'reported_user_id': reportedUserId,
        'category': _category,
        'description': _descCtrl.text.trim(),
      });

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
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
            title: const Text('Report Submitted'),
            content: const Text(
                'Your report has been submitted. Our team will review it and get back to you.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.pop();
                },
                child: const Text('Done'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _descCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Report an Issue')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_booking != null)
                    Container(
                      padding: AppSpacing.cardPadding,
                      decoration: BoxDecoration(
                        color: AppColors.cardLight,
                        borderRadius: AppRadius.lgAll,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: AppRadius.mdAll,
                            ),
                            child: const Icon(Icons.flag_outlined,
                                color: AppColors.warning, size: 22),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                    _booking?['services']?['service_name'] ??
                                        'Booking',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall),
                                const SizedBox(height: 2),
                                Text(
                                  'Report about this booking',
                                  style:
                                      Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                  const SizedBox(height: AppSpacing.xxl),

                  Text('Issue Category',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: _categories.entries.map((e) {
                      final selected = _category == e.key;
                      return ChoiceChip(
                        label: Text(e.value),
                        selected: selected,
                        onSelected: (_) =>
                            setState(() => _category = e.key),
                        selectedColor:
                            AppColors.primary.withValues(alpha: 0.15),
                        labelStyle: TextStyle(
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          fontWeight: selected
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: AppSpacing.xxl),

                  Text('Describe the Issue',
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _descCtrl,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText:
                          'Please provide details about what happened...',
                      border:
                          OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    ),
                  ),

                  const SizedBox(height: AppSpacing.xxxl),

                  FilledButton.icon(
                    onPressed: _submitting ? null : _submit,
                    icon: _submitting
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send_rounded),
                    label: Text(
                        _submitting ? 'Submitting...' : 'Submit Report'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.error,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
    );
  }
}
