import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../services/location_service.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/price_offer_sheet.dart';

class BookingScreen extends StatefulWidget {
  final String providerId;
  final String serviceId;
  final String? packageId;
  const BookingScreen({
    super.key,
    required this.providerId,
    required this.serviceId,
    this.packageId,
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

  // Price negotiation
  double? _offeredPrice;
  bool _isNegotiated = false;

  // Promo code state
  Map<String, dynamic>? _appliedPromo;
  double _discountAmount = 0;
  bool _applyingPromo = false;
  String? _promoError;

  // Add-ons
  List<Map<String, dynamic>> _addons = [];
  final Set<String> _selectedAddonIds = {};

  // Payment method
  String _paymentMethod = 'cash';

  // Travel fee (estimate; the server recalculates from the same inputs)
  double _travelFee = 0;
  Map<String, dynamic>? _providerProfile;
  double? _clientLat;
  double? _clientLng;
  bool _locating = false;

  // Package booking
  Map<String, dynamic>? _package;

  // Cancellation policy
  Map<String, dynamic>? _cancelPolicy;

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

      final uid = supabase.auth.currentUser?.id;
      if (uid == null) return;

      final clientProfile = await supabase
          .from('profiles')
          .select()
          .eq('id', uid)
          .maybeSingle();

      // Load add-ons for this service
      List<Map<String, dynamic>> addons = [];
      try {
        addons = await supabase
            .from('service_addons')
            .select()
            .eq('service_id', widget.serviceId)
            .eq('is_active', true)
            .order('sort_order');
      } catch (_) {}

      // Load provider profile for travel fee info
      Map<String, dynamic>? pp;
      try {
        pp = await supabase
            .from('provider_profiles')
            .select()
            .eq('provider_id', widget.providerId)
            .maybeSingle();
      } catch (_) {}

      Map<String, dynamic>? package;
      if (widget.packageId != null) {
        package = await supabase
            .from('service_packages')
            .select('*, package_services(services(service_name, duration_minutes))')
            .eq('id', widget.packageId!)
            .eq('provider_id', widget.providerId)
            .eq('is_active', true)
            .maybeSingle();
      }

      // Load cancellation policy
      Map<String, dynamic>? policy;
      try {
        policy = await supabase
            .from('cancellation_policies')
            .select()
            .eq('provider_id', widget.providerId)
            .maybeSingle();
      } catch (_) {}

      if (mounted) {
        setState(() {
          _provider = provider;
          _service = service;
          _addressCtrl.text = clientProfile?['location'] ?? '';
          _addons = List<Map<String, dynamic>>.from(addons);
          _providerProfile = pp;
          _cancelPolicy = policy;
          _package = package;
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

  int get _baseDuration {
    if (_package != null) {
      final items = (_package!['package_services'] as List?) ?? [];
      final total = items.fold<int>(0, (sum, ps) =>
          sum + (((ps['services']?['duration_minutes']) as int?) ?? 0));
      if (total > 0) return total;
    }
    return (_service?['duration_minutes'] as int?) ?? 60;
  }

  Future<String?> _slotProblem(DateTime bookingDateTime) async {
    final res = await supabase.rpc('check_slot', params: {
      'p_provider': widget.providerId,
      'p_start': bookingDateTime.toUtc().toIso8601String(),
      'p_minutes': _baseDuration + _addonsDuration,
    });
    return res as String?;
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentPosition();
      if (pos == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Location unavailable — travel fee will be agreed with your stylist.')));
        }
        return;
      }
      setState(() {
        _clientLat = pos.latitude;
        _clientLng = pos.longitude;
        _travelFee = _estimateTravelFee();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  double _estimateTravelFee() {
    final pp = _providerProfile;
    final perKm = (pp?['travel_fee_per_km'] as num?)?.toDouble() ?? 0;
    final lat = (pp?['latitude'] as num?)?.toDouble();
    final lng = (pp?['longitude'] as num?)?.toDouble();
    if (perKm <= 0 || lat == null || lng == null || _clientLat == null) return 0;
    double rad(double d) => d * math.pi / 180;
    final dLat = rad(_clientLat! - lat);
    final dLng = rad(_clientLng! - lng);
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(rad(lat)) * math.cos(rad(_clientLat!)) * math.pow(math.sin(dLng / 2), 2);
    final km = 6371 * 2 * math.asin(math.sqrt(a));
    final free = (pp?['free_travel_radius_km'] as num?)?.toDouble() ?? 0;
    final maxFee = (pp?['max_travel_fee'] as num?)?.toDouble() ?? 20;
    final fee = math.min(maxFee, math.max(0, km - free) * perKm);
    return (fee * 100).roundToDouble() / 100;
  }

  double get _servicePrice => _package != null
      ? (_package!['package_price'] as num?)?.toDouble() ?? 0
      : (_service?['price'] as num?)?.toDouble() ?? 0;

  double get _addonsTotal {
    double total = 0;
    for (final addon in _addons) {
      if (_selectedAddonIds.contains(addon['id'])) {
        total += (addon['price'] as num?)?.toDouble() ?? 0;
      }
    }
    return total;
  }

  int get _addonsDuration {
    int total = 0;
    for (final addon in _addons) {
      if (_selectedAddonIds.contains(addon['id'])) {
        total += (addon['duration_minutes'] as int?) ?? 0;
      }
    }
    return total;
  }

  double get _effectivePrice => _offeredPrice ?? _servicePrice;

  double get _totalPrice =>
      (_effectivePrice + _addonsTotal + _travelFee - _discountAmount)
          .clamp(0, double.infinity);

  Future<void> _openPriceOffer() async {
    final result = await showModalBottomSheet<double>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => PriceOfferSheet(
        listedPrice: _servicePrice,
        serviceName: _service!['service_name'] ?? 'Service',
        providerName: _provider!['full_name'] ?? 'Provider',
      ),
    );
    if (result != null && mounted) {
      setState(() {
        _offeredPrice = result;
        _isNegotiated = result != _servicePrice;
      });
    }
  }

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
      final rows = await supabase.rpc('check_promo', params: {
        'p_provider': widget.providerId,
        'p_code': code,
        'p_amount': _effectivePrice,
      }) as List;
      final res = rows.isNotEmpty ? rows.first as Map<String, dynamic> : null;
      if (res == null || res['error'] != null) {
        if (mounted) setState(() => _promoError = res?['error'] ?? 'Invalid promo code');
        return;
      }
      setState(() {
        _appliedPromo = {'code': code};
        _discountAmount = (res['discount'] as num).toDouble();
      });
    } catch (e) {
      if (mounted) setState(() => _promoError = 'Error applying promo code');
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
      final currentUid = supabase.auth.currentUser?.id;
      if (currentUid == null) return;

      final me = await supabase
          .from('profiles')
          .select('is_activated')
          .eq('id', currentUid)
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

      final problem = await _slotProblem(bookingDateTime);
      if (problem != null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(problem), backgroundColor: AppColors.error),
          );
        }
        setState(() => _submitting = false);
        return;
      }

      final bookingData = {
        'client_id': currentUid,
        'provider_id': widget.providerId,
        'service_id': widget.serviceId,
        'booking_time': bookingDateTime.toUtc().toIso8601String(),
        'address': _addressCtrl.text.trim(),
        'status': 'pending',
        'total_price': _totalPrice,
        'discount_amount': _discountAmount,
        'promo_code': _appliedPromo?['code'],
        'payment_method': _paymentMethod,
        'addons_total': _addonsTotal,
        'travel_fee': _travelFee,
        if (_package != null) 'package_id': _package!['id'],
        if (_clientLat != null) 'client_lat': _clientLat,
        if (_clientLng != null) 'client_lng': _clientLng,
        'client_note':
            _noteCtrl.text.trim().isEmpty ? null : _noteCtrl.text.trim(),
        if (_isNegotiated) ...{
          'client_offered_price': _offeredPrice,
          'negotiation_status': 'client_offered',
          'negotiation_rounds': 1,
          'offer_expires_at': DateTime.now()
              .add(const Duration(hours: 24))
              .toUtc().toIso8601String(),
        },
      };

      final insertedRows = await supabase
          .from('bookings')
          .insert(bookingData)
          .select('id')
          .single();
      final bookingId = insertedRows['id'] as String;

      // Insert selected add-ons
      if (_selectedAddonIds.isNotEmpty) {
        final addonRows = _addons
            .where((a) => _selectedAddonIds.contains(a['id']))
            .map((a) => ({
                  'booking_id': bookingId,
                  'addon_id': a['id'],
                  'addon_name': a['name'],
                  'addon_price': a['price'],
                  'addon_duration': a['duration_minutes'] ?? 0,
                }))
            .toList();
        await supabase.from('booking_addons').insert(addonRows);
      }

      // Notify provider
      final clientName = (await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', currentUid)
              .maybeSingle())?['full_name'] ??
          'A client';
      NotificationService.send(
        userId: widget.providerId,
        type: 'booking',
        title: _isNegotiated ? 'New Price Offer' : 'New Booking Request',
        body: _isNegotiated
            ? '$clientName offered \$${_offeredPrice!.toStringAsFixed(0)} for ${_service!['service_name']} (listed \$${_servicePrice.toStringAsFixed(0)})'
            : '$clientName booked ${_service!['service_name']}',
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
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.message.contains('ACTIVATION_REQUIRED')) {
        context.push('/activation');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
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
                border: Border.all(color: AppColors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
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
                        child: Icon(categoryIcon(_package != null ? 'package' : cat?['name']),
                            size: 26, color: AppColors.primary),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_package?['name'] ?? _service!['service_name'],
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              _package != null
                                  ? 'Package · $_baseDuration min'
                                  : '${cat?['name'] ?? ''} · $_baseDuration min',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 2),
                            Text('with ${_provider!['full_name']}',
                                style: Theme.of(context).textTheme.bodyMedium),
                          ],
                        ),
                      ),
                      Text('\$${_servicePrice.toStringAsFixed(_servicePrice % 1 == 0 ? 0 : 2)}',
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
            if (((_providerProfile?['travel_fee_per_km'] as num?) ?? 0) > 0) ...[
              const SizedBox(height: AppSpacing.sm),
              Row(children: [
                TextButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: Text(_clientLat == null
                      ? 'Use my location for travel fee'
                      : 'Location set'),
                ),
                const Spacer(),
                if (_clientLat != null)
                  Text(
                    _travelFee > 0
                        ? 'Travel: \$${_travelFee.toStringAsFixed(2)}'
                        : 'No travel fee',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ]),
            ],

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

            // Add-ons section
            if (_addons.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('Add-ons (Optional)',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  children: _addons.map((addon) {
                    final selected = _selectedAddonIds.contains(addon['id']);
                    final price = (addon['price'] as num?)?.toDouble() ?? 0;
                    final dur = (addon['duration_minutes'] as int?) ?? 0;
                    return CheckboxListTile(
                      value: selected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selectedAddonIds.add(addon['id']);
                          } else {
                            _selectedAddonIds.remove(addon['id']);
                          }
                        });
                      },
                      title: Text(addon['name'] ?? '',
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        '+\$${price.toStringAsFixed(2)}${dur > 0 ? ' · +$dur min' : ''}',
                        style: TextStyle(
                          fontSize: 12,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textTertiary,
                        ),
                      ),
                      activeColor: AppColors.primary,
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll),
                    );
                  }).toList(),
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),

            // Payment method
            Text('Payment Method',
                style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                _PaymentChip(
                  label: 'Cash',
                  icon: Icons.money_rounded,
                  selected: _paymentMethod == 'cash',
                  onTap: () => setState(() => _paymentMethod = 'cash'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _PaymentChip(
                  label: 'EcoCash',
                  icon: Icons.phone_android_rounded,
                  selected: _paymentMethod == 'ecocash',
                  onTap: () => setState(() => _paymentMethod = 'ecocash'),
                ),
                const SizedBox(width: AppSpacing.sm),
                _PaymentChip(
                  label: 'PayNow',
                  icon: Icons.account_balance_rounded,
                  selected: _paymentMethod == 'paynow',
                  onTap: () => setState(() => _paymentMethod = 'paynow'),
                ),
              ],
            ),

            // Cancellation policy
            if (_cancelPolicy != null) ...[
              const SizedBox(height: AppSpacing.xxl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.06),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: AppColors.warning.withValues(alpha: 0.2)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: AppColors.warning, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Cancellation Policy',
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13)),
                          const SizedBox(height: 4),
                          Text(
                            'Free cancellation up to ${_cancelPolicy!['free_cancel_hours']}h before. '
                            'Late cancel: ${_cancelPolicy!['late_cancel_fee_percent']}% fee. '
                            'No-show: ${_cancelPolicy!['no_show_fee_percent']}% fee.',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],

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
                        backgroundColor: AppColors.primarySoft,
                        foregroundColor: AppColors.primary,
                        minimumSize: const Size(0, 48),
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

            // Offer your price
            Container(
              decoration: BoxDecoration(
                color: _isNegotiated
                    ? AppColors.success.withValues(alpha: 0.05)
                    : AppColors.primary.withValues(alpha: 0.04),
                borderRadius: AppRadius.lgAll,
                border: Border.all(
                  color: _isNegotiated
                      ? AppColors.success.withValues(alpha: 0.3)
                      : AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: AppRadius.lgAll,
                child: InkWell(
                  borderRadius: AppRadius.lgAll,
                  onTap: _openPriceOffer,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: _isNegotiated
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.primary.withValues(alpha: 0.1),
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Icon(
                            _isNegotiated
                                ? Icons.check_circle_rounded
                                : Icons.local_offer_outlined,
                            color: _isNegotiated
                                ? AppColors.success
                                : AppColors.primary,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _isNegotiated
                                    ? 'Your Offer: \$${_offeredPrice!.toStringAsFixed(0)}'
                                    : 'Offer Your Price',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: _isNegotiated
                                      ? AppColors.success
                                      : AppColors.textPrimary,
                                ),
                              ),
                              Text(
                                _isNegotiated
                                    ? 'Listed: \$${_servicePrice.toStringAsFixed(0)} — Tap to change'
                                    : 'Suggest a price for this service',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: AppColors.textTertiary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Price summary card
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: AppColors.border),
              ),
              child: Column(children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Service',
                        style: Theme.of(context).textTheme.bodyMedium),
                    Text(
                      '\$${_servicePrice.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: _isNegotiated
                            ? AppColors.textTertiary
                            : AppColors.textPrimary,
                        decoration: _isNegotiated
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                  ],
                ),
                if (_isNegotiated) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.local_offer_outlined,
                              size: 14, color: AppColors.primary),
                          const SizedBox(width: 4),
                          const Text('Your offer',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.primary)),
                        ],
                      ),
                      Text(
                        '\$${_offeredPrice!.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_addonsTotal > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Add-ons (${_selectedAddonIds.length})',
                          style: const TextStyle(fontSize: 14)),
                      Text(
                        '+\$${_addonsTotal.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
                if (_travelFee > 0) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Travel fee',
                          style: TextStyle(fontSize: 14)),
                      Text(
                        '+\$${_travelFee.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
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
                  color: AppColors.border,
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
                Text(
                  _paymentMethod == 'cash'
                      ? 'Cash payment at time of service'
                      : _paymentMethod == 'ecocash'
                          ? 'Pay via EcoCash'
                          : 'Pay via PayNow',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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

class _PaymentChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _PaymentChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: selected
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.cardLight,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: Container(
            padding: const EdgeInsets.symmetric(
                vertical: AppSpacing.md, horizontal: AppSpacing.sm),
            decoration: BoxDecoration(
              borderRadius: AppRadius.mdAll,
              border: Border.all(
                color: selected
                    ? AppColors.primary
                    : AppColors.borderStrong,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              children: [
                Icon(icon,
                    size: 22,
                    color:
                        selected ? AppColors.primary : AppColors.textTertiary),
                const SizedBox(height: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
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
                  : AppColors.borderStrong,
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
