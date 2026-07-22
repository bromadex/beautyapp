import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class BookingScreen extends StatefulWidget {
  final String providerId;
  final String serviceId;
  const BookingScreen({
    super.key,
    required this.providerId,
    required this.serviceId,
  });
  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  Map<String, dynamic>? _provider;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  final _addressCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  final _promoCtrl = TextEditingController();
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;

  // Promo code state
  Map<String, dynamic>? _appliedPromo;
  double _discountAmount = 0;
  bool _applyingPromo = false;
  String? _promoError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final provider = await supabase
          .from('profiles')
          .select()
          .eq('id', widget.providerId)
          .maybeSingle();

      final service = await supabase
          .from('services')
          .select('*, service_categories(name, icon)')
          .eq('id', widget.serviceId)
          .maybeSingle();

      if (provider == null || service == null) {
        setState(() {
          _error = 'Could not load booking details';
          _loading = false;
        });
        return;
      }

      final clientProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', supabase.auth.currentUser!.id)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _provider = provider;
          _service = service;
          _addressCtrl.text = clientProfile?['location'] ?? '';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 60)),
    );
    if (date != null) setState(() => _selectedDate = date);
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 10, minute: 0),
    );
    if (time != null) setState(() => _selectedTime = time);
  }

  Future<bool> _hasConflict(DateTime bookingDateTime) async {
    final service = _service!;
    final durationMinutes = (service['duration_minutes'] as int?) ?? 60;
    final bookingEnd = bookingDateTime.add(Duration(minutes: durationMinutes));

    final existing = await supabase
        .from('bookings')
        .select('booking_time, services(duration_minutes)')
        .eq('provider_id', widget.providerId)
        .inFilter('status', ['pending', 'confirmed']);

    for (final b in existing as List) {
      final existingStart = DateTime.parse(b['booking_time']);
      final existingDur = (b['services']?['duration_minutes'] as int?) ?? 60;
      final existingEnd = existingStart.add(Duration(minutes: existingDur));

      if (bookingDateTime.isBefore(existingEnd) &&
          bookingEnd.isAfter(existingStart)) {
        return true;
      }
    }
    return false;
  }

  double get _servicePrice =>
      (_service?['price'] as num?)?.toDouble() ?? 0;

  double get _totalPrice => (_servicePrice - _discountAmount).clamp(0, double.infinity);

  Future<void> _applyPromo() async {
    final code = _promoCtrl.text.trim().toUpperCase();
    if (code.isEmpty) return;

    setState(() {
      _applyingPromo = true;
      _promoError = null;
      _appliedPromo = null;
      _discountAmount = 0;
    });

    try {
      final results = await supabase
          .from('promotions')
          .select()
          .eq('provider_id', widget.providerId)
          .ilike('code', code)
          .eq('is_active', true)
          .limit(1);

      if (results.isEmpty) {
        setState(() => _promoError = 'Invalid promo code');
        return;
      }

      final promo = results[0] as Map<String, dynamic>;

      // Check expiry
      if (promo['valid_until'] != null) {
        final validUntil = DateTime.parse(promo['valid_until']);
        if (validUntil.isBefore(DateTime.now())) {
          setState(() => _promoError = 'This promo code has expired');
          return;
        }
      }

      // Check max uses
      if (promo['max_uses'] != null &&
          (promo['used_count'] ?? 0) >= promo['max_uses']) {
        setState(() => _promoError = 'This promo code has reached its limit');
        return;
      }

      // Check min order amount
      final minOrder =
          (promo['min_order_amount'] as num?)?.toDouble() ?? 0;
      if (_servicePrice < minOrder) {
        setState(() => _promoError =
            'Min order \$${minOrder.toStringAsFixed(0)} required');
        return;
      }

      // Calculate discount
      double discount;
      if (promo['discount_type'] == 'percentage') {
        discount =
            _servicePrice * (promo['discount_value'] as num).toDouble() / 100;
      } else {
        discount = (promo['discount_value'] as num).toDouble();
      }
      discount = discount.clamp(0, _servicePrice);

      setState(() {
        _appliedPromo = promo;
        _discountAmount = discount;
      });
    } catch (e) {
      setState(() => _promoError = 'Error applying promo code');
    } finally {
      if (mounted) setState(() => _applyingPromo = false);
    }
  }

  void _removePromo() {
    setState(() {
      _appliedPromo = null;
      _discountAmount = 0;
      _promoCtrl.clear();
      _promoError = null;
    });
  }

  Future<void> _confirmBooking() async {
    if (_selectedDate == null || _selectedTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a date and time')),
      );
      return;
    }
    if (_addressCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your address')),
      );
      return;
    }

    final bookingDateTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    if (bookingDateTime.isBefore(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a future date and time')),
      );
      return;
    }

    setState(() => _submitting = true);

    try {
      // Stage 19: activation gate — unactivated clients pay the one-time $1 fee first.
      // Null (column not yet migrated) is treated as activated so the app never bricks.
      final me = await supabase
          .from('profiles')
          .select('is_activated')
          .eq('id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (me != null && me['is_activated'] == false) {
        setState(() => _submitting = false);
        if (mounted) context.push('/activation');
        return;
      }

      // Provider activation gate: providers can be browsed and messaged for
      // free, but can only RECEIVE bookings with an active subscription
      // ($3 activation, then $5/month). No subscription row → not bookable.
      try {
        final sub = await supabase
            .from('subscriptions')
            .select('status, end_date')
            .eq('provider_id', widget.providerId)
            .maybeSingle();
        final end = DateTime.tryParse(sub?['end_date'] ?? '');
        final providerActive = sub != null &&
            sub['status'] == 'active' &&
            end != null &&
            end.isAfter(DateTime.now());
        if (!providerActive) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                    'This stylist isn\'t accepting bookings yet. You can still message them!'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
          setState(() => _submitting = false);
          return;
        }
      } catch (_) {
        // Subscriptions table unreachable — don't block the client
      }

      final pp = await supabase
          .from('provider_profiles')
          .select('availability_status')
          .eq('provider_id', widget.providerId)
          .maybeSingle();

      if (pp?['availability_status'] == 'busy') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('This provider is currently busy'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
        setState(() => _submitting = false);
        return;
      }

      final conflict = await _hasConflict(bookingDateTime);
      if (conflict) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                  'The provider already has a booking at that time. Please choose another slot.'),
              backgroundColor: AppColors.error,
            ),
          );
        }
        setState(() => _submitting = false);
        return;
      }

      await supabase.from('bookings').insert({
        'client_id': supabase.auth.currentUser!.id,
        'provider_id': widget.providerId,
        'service_id': widget.serviceId,
        'booking_time': bookingDateTime.toIso8601String(),
        'address': _addressCtrl.text.trim(),
        'status': 'pending',
        'total_price': _totalPrice,
        'discount_amount': _discountAmount,
        'promo_code': _appliedPromo?['code'],
        'client_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
      });

      // Increment promo used_count
      if (_appliedPromo != null) {
        await supabase.from('promotions').update({
          'used_count': (_appliedPromo!['used_count'] ?? 0) + 1,
        }).eq('id', _appliedPromo!['id']);
      }

      // Notify provider
      final clientName = (await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', supabase.auth.currentUser!.id)
              .maybeSingle())?['full_name'] ??
          'A client';
      NotificationService.send(
        userId: widget.providerId,
        type: 'booking',
        title: 'New Booking Request',
        body: '$clientName booked ${_service!['service_name']}',
      );

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
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppColors.success,
                size: 40,
              ),
            ),
            title: const Text('Booking Sent!'),
            content: const Text(
                'Your booking request has been sent to the provider. '
                'You\'ll be notified once they confirm.'),
            actions: [
              FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/client/bookings');
                },
                child: const Text('View My Bookings'),
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
    _addressCtrl.dispose();
    _noteCtrl.dispose();
    _promoCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Book Appointment')),
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

    final cat = _service!['service_categories'] as Map?;
    final dateStr = _selectedDate == null
        ? 'Select date'
        : '${_selectedDate!.day}/${_selectedDate!.month}/${_selectedDate!.year}';
    final timeStr = _selectedTime == null
        ? 'Select time'
        : _selectedTime!.format(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Book Appointment')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Service summary card with gradient accent
            Container(
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  // Gradient accent strip
                  Container(
                    height: 4,
                    decoration: const BoxDecoration(
                      gradient: AppColors.primaryGradient,
                    ),
                  ),
                  Padding(
                    padding: AppSpacing.cardPadding,
                    child: Row(children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: AppRadius.mdAll,
                        ),
                        alignment: Alignment.center,
                        child: Text(cat?['icon'] ?? '',
                            style: const TextStyle(fontSize: 26)),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_service!['service_name'],
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              '${cat?['name'] ?? ''} -- ${_service!['duration_minutes']} min',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text('with ${_provider!['full_name']}',
                                style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      Text('\$${_service!['price']}',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(color: AppColors.primary)),
                    ]),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Section header
            Text('Date & Time',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),

            // Date and time picker cards
            Row(children: [
              Expanded(
                child: _PickerCard(
                  icon: Icons.calendar_month_outlined,
                  label: 'Date',
                  value: dateStr,
                  isSelected: _selectedDate != null,
                  onTap: _pickDate,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _PickerCard(
                  icon: Icons.access_time_rounded,
                  label: 'Time',
                  value: timeStr,
                  isSelected: _selectedTime != null,
                  onTap: _pickTime,
                ),
              ),
            ]),

            const SizedBox(height: AppSpacing.xxl),

            // Address section
            Text('Your Address',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),

            TextFormField(
              controller: _addressCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. 12 Borrowdale Rd, Harare',
                prefixIcon: Icon(Icons.location_on_outlined),
              ),
              maxLines: 2,
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Note section
            Text('Note to Provider (optional)',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),

            TextFormField(
              controller: _noteCtrl,
              decoration: const InputDecoration(
                hintText: 'e.g. Please bring your own products',
              ),
              maxLines: 3,
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Promo code section
            Text('Promo Code', style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            if (_appliedPromo != null)
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.05),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: const Icon(Icons.check_circle_rounded,
                          color: AppColors.success, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _appliedPromo!['code'],
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.success,
                              letterSpacing: 1,
                            ),
                          ),
                          Text(
                            '-\$${_discountAmount.toStringAsFixed(2)} discount applied',
                            style: const TextStyle(
                                fontSize: 12, color: AppColors.success),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: _removePromo,
                      icon: const Icon(Icons.close_rounded, size: 20),
                      color: AppColors.textTertiary,
                    ),
                  ],
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _promoCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        hintText: 'Enter promo code',
                        prefixIcon:
                            const Icon(Icons.confirmation_number_outlined),
                        errorText: _promoError,
                        border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    height: 48,
                    child: FilledButton(
                      onPressed: _applyingPromo ? null : _applyPromo,
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.secondary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll),
                      ),
                      child: _applyingPromo
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Text('Apply'),
                    ),
                  ),
                ],
              ),

            const SizedBox(height: AppSpacing.xxl),

            // Price summary card
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Service',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text('\$${_servicePrice.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.bodyLarge),
                  ],
                ),
                if (_discountAmount > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_offer_outlined,
                              size: 14, color: AppColors.success),
                          const SizedBox(width: 4),
                          Text('Discount (${_appliedPromo!['code']})',
                              style: const TextStyle(
                                  fontSize: 14, color: AppColors.success)),
                        ],
                      ),
                      Text(
                        '-\$${_discountAmount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ],
                Divider(
                  height: AppSpacing.xxl,
                  color: Colors.grey.shade200,
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total',
                        style: Theme.of(context).textTheme.titleMedium),
                    Text('\$${_totalPrice.toStringAsFixed(2)}',
                        style: Theme.of(context)
                            .textTheme
                            .titleLarge
                            ?.copyWith(color: AppColors.primary)),
                  ],
                ),
                if (_discountAmount > 0) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'You save \$${_discountAmount.toStringAsFixed(2)}!',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.success,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.xs),
                Text('Payment collected at time of service',
                    style: Theme.of(context).textTheme.bodySmall),
              ]),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Confirm button
            FilledButton.icon(
              onPressed: _submitting ? null : _confirmBooking,
              icon: _submitting
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.check_circle_outline),
              label: Text(_submitting
                  ? 'Sending Request...'
                  : 'Confirm Booking Request'),
            ),

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

/// A styled card for date/time picker triggers.
class _PickerCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool isSelected;
  final VoidCallback onTap;

  const _PickerCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: isSelected
          ? AppColors.primary.withValues(alpha: 0.05)
          : AppColors.cardLight,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: isSelected
                  ? AppColors.primary.withValues(alpha: 0.4)
                  : Colors.grey.shade300,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 22,
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.textTertiary),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: Theme.of(context).textTheme.labelSmall),
                    const SizedBox(height: 2),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: isSelected
                                ? AppColors.textPrimary
                                : AppColors.textTertiary,
                          ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
