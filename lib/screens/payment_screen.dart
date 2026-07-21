import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../config/app_config.dart';
import '../theme.dart';
import '../widgets/payment_method_card.dart';

class PaymentScreen extends StatefulWidget {
  final String bookingId;
  const PaymentScreen({super.key, required this.bookingId});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _service;
  bool _loading = true;
  bool _processing = false;
  String _selectedMethod = 'card';

  // Mobile money fields
  final _mobileNumberCtrl = TextEditingController();
  String _selectedNetwork = 'EcoCash';
  final List<String> _networks = ['EcoCash', 'OneMoney', 'Telecash'];

  @override
  void initState() {
    super.initState();
    _loadBooking();
  }

  Future<void> _loadBooking() async {
    try {
      final booking = await supabase
          .from('bookings')
          .select('*, services(service_name, price, duration_minutes), profiles!bookings_provider_id_fkey(full_name)')
          .eq('id', widget.bookingId)
          .maybeSingle();

      if (booking == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Booking not found')),
          );
          context.go('/home');
        }
        return;
      }

      setState(() {
        _booking = booking;
        _service = booking['services'];
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading booking: $e')),
        );
        context.go('/home');
      }
    }
  }

  double get _amount =>
      (_booking?['total_price'] as num?)?.toDouble() ??
      (_service?['price'] as num?)?.toDouble() ??
      0.0;
  double get _originalPrice =>
      (_service?['price'] as num?)?.toDouble() ?? 0.0;
  double get _discountAmount =>
      (_booking?['discount_amount'] as num?)?.toDouble() ?? 0.0;
  double get _fee => AppConfig.calculatePlatformFee(_amount);
  double get _providerEarnings => AppConfig.calculateProviderEarnings(_amount);

  String _generateRef() =>
      'TXN-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  Future<void> _processPayment() async {
    if (_selectedMethod == 'mobile_money' &&
        _mobileNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please enter your mobile number'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _processing = true);

    try {
      final uid = supabase.auth.currentUser!.id;
      final ref = _generateRef();
      final now = DateTime.now().toIso8601String();

      final isCod = _selectedMethod == 'cash_on_delivery';
      final paymentStatus = isCod ? 'pending' : 'paid';
      final bookingPaymentStatus = isCod ? 'cod_pending' : 'paid';

      // Simulate processing delay for card/mobile money
      if (!isCod) {
        await Future.delayed(const Duration(seconds: 2));
      }

      // Insert payment record
      await supabase.from('payments').insert({
        'booking_id': widget.bookingId,
        'client_id': uid,
        'provider_id': _booking!['provider_id'],
        'amount': _amount,
        'platform_fee': _fee,
        'provider_earnings': _providerEarnings,
        'method': _selectedMethod,
        'status': paymentStatus,
        'transaction_ref': ref,
        'paid_at': isCod ? null : now,
      });

      // Update booking payment status
      await supabase.from('bookings').update({
        'payment_status': bookingPaymentStatus,
      }).eq('id', widget.bookingId);

      if (mounted) {
        _showSuccessDialog(isCod, ref);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment failed: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _showSuccessDialog(bool isCod, String ref) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        contentPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, AppSpacing.xxxl, AppSpacing.xxl, AppSpacing.lg,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Celebratory icon with layered rings
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: (isCod ? AppColors.warning : AppColors.success)
                    .withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: (isCod ? AppColors.warning : AppColors.success)
                      .withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isCod ? Icons.handshake_rounded : Icons.check_circle_rounded,
                  color: isCod ? AppColors.warning : AppColors.success,
                  size: 48,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(
              isCod ? 'Booking Confirmed!' : 'Payment Successful!',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              isCod
                  ? 'You will pay \$${_amount.toStringAsFixed(2)} in cash when the service is completed.'
                  : 'Your payment of \$${_amount.toStringAsFixed(2)} was processed successfully.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs + 2,
              ),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'Ref: $ref',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppColors.textTertiary,
                  fontFamily: 'monospace',
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(
          AppSpacing.xxl, 0, AppSpacing.xxl, AppSpacing.xxl,
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/client/bookings');
              },
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('View My Bookings'),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _mobileNumberCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    final providerName = _booking?['profiles']?['full_name'] ?? 'Provider';

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order summary card
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius: AppRadius.smAll,
                        ),
                        child: const Icon(
                          Icons.receipt_long_rounded,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(
                        'Order Summary',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _SummaryRow(
                    label: 'Service',
                    value: _service?['service_name'] ?? '--',
                  ),
                  _SummaryRow(label: 'Provider', value: providerName),
                  _SummaryRow(
                    label: 'Duration',
                    value: '${_service?['duration_minutes'] ?? '--'} mins',
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                    child: Divider(color: Colors.grey.shade200),
                  ),
                  _SummaryRow(
                    label: 'Service Price',
                    value: '\$${_originalPrice.toStringAsFixed(2)}',
                  ),
                  if (_discountAmount > 0)
                    _SummaryRow(
                      label: 'Discount${_booking?['promo_code'] != null ? ' (${_booking!['promo_code']})' : ''}',
                      value: '-\$${_discountAmount.toStringAsFixed(2)}',
                      valueColor: AppColors.success,
                    ),
                  _SummaryRow(
                    label: 'Platform Fee (10%)',
                    value: '\$${_fee.toStringAsFixed(2)}',
                    valueColor: AppColors.textTertiary,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Total',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          '\$${_amount.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 20,
                            color: AppColors.primary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxxl),

            // Payment methods
            Text(
              'Select Payment Method',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.lg),

            PaymentMethodCard(
              title: 'Credit / Debit Card',
              subtitle: 'Visa, Mastercard -- simulated for now',
              icon: Icons.credit_card_rounded,
              value: 'card',
              selectedValue: _selectedMethod,
              onTap: (v) => setState(() => _selectedMethod = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            PaymentMethodCard(
              title: 'Mobile Money',
              subtitle: 'EcoCash, OneMoney, Telecash',
              icon: Icons.phone_android_rounded,
              value: 'mobile_money',
              selectedValue: _selectedMethod,
              onTap: (v) => setState(() => _selectedMethod = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            PaymentMethodCard(
              title: 'Cash on Delivery',
              subtitle: 'Pay the stylist in cash after the service',
              icon: Icons.payments_rounded,
              value: 'cash_on_delivery',
              selectedValue: _selectedMethod,
              onTap: (v) => setState(() => _selectedMethod = v),
            ),

            // Mobile money fields
            if (_selectedMethod == 'mobile_money') ...[
              const SizedBox(height: AppSpacing.xxl),
              Text(
                'Mobile Money Details',
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                value: _selectedNetwork,
                decoration: const InputDecoration(
                  labelText: 'Network',
                ),
                items: _networks
                    .map((n) => DropdownMenuItem(value: n, child: Text(n)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedNetwork = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _mobileNumberCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: '077XXXXXXX',
                  prefixIcon: Icon(Icons.phone_rounded),
                ),
              ),
            ],

            // COD notice
            if (_selectedMethod == 'cash_on_delivery') ...[
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.08),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xs),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withValues(alpha: 0.15),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: const Icon(Icons.info_outline_rounded,
                          color: AppColors.warning, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    const Expanded(
                      child: Text(
                        'You will pay the stylist directly in cash when the service is done. Please have the exact amount ready.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.xxxl),

            // Pay button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _processing ? null : _processPayment,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _processing
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _selectedMethod == 'cash_on_delivery'
                            ? 'Confirm Booking (Pay Later)'
                            : 'Pay \$${_amount.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SummaryRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: valueColor ?? AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
