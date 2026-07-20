import 'dart:math';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../config/app_config.dart';
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

  double get _amount => (_service?['price'] as num?)?.toDouble() ?? 0.0;
  double get _fee => AppConfig.calculatePlatformFee(_amount);
  double get _providerEarnings => AppConfig.calculateProviderEarnings(_amount);

  String _generateRef() =>
      'TXN-${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(9999)}';

  Future<void> _processPayment() async {
    if (_selectedMethod == 'mobile_money' &&
        _mobileNumberCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter your mobile number')),
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
          SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isCod ? Icons.handshake_rounded : Icons.check_circle_rounded,
              color: isCod ? Colors.orange : Colors.green,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              isCod ? 'Booking Confirmed!' : 'Payment Successful!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              isCod
                  ? 'You will pay \$${_amount.toStringAsFixed(2)} in cash when the service is completed.'
                  : 'Your payment of \$${_amount.toStringAsFixed(2)} was processed successfully.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 8),
            Text('Ref: $ref',
                style: const TextStyle(
                    fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                context.go('/client/bookings');
              },
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final providerName = _booking?['profiles']?['full_name'] ?? 'Provider';

    return Scaffold(
      appBar: AppBar(title: const Text('Payment')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Order summary
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Order Summary',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 14),
                  _SummaryRow(label: 'Service', value: _service?['service_name'] ?? '—'),
                  _SummaryRow(label: 'Provider', value: providerName),
                  _SummaryRow(label: 'Duration', value: '${_service?['duration_minutes'] ?? '—'} mins'),
                  const Divider(height: 24),
                  _SummaryRow(label: 'Service Price', value: '\$${_amount.toStringAsFixed(2)}'),
                  _SummaryRow(label: 'Platform Fee (10%)', value: '\$${_fee.toStringAsFixed(2)}', valueColor: Colors.grey),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('\$${_amount.toStringAsFixed(2)}',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Theme.of(context).colorScheme.primary)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 28),

            // Payment methods
            const Text('Select Payment Method',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 14),

            PaymentMethodCard(
              title: 'Credit / Debit Card',
              subtitle: 'Visa, Mastercard — simulated for now',
              icon: Icons.credit_card_rounded,
              value: 'card',
              selectedValue: _selectedMethod,
              onTap: (v) => setState(() => _selectedMethod = v),
            ),
            const SizedBox(height: 10),
            PaymentMethodCard(
              title: 'Mobile Money',
              subtitle: 'EcoCash, OneMoney, Telecash',
              icon: Icons.phone_android_rounded,
              value: 'mobile_money',
              selectedValue: _selectedMethod,
              onTap: (v) => setState(() => _selectedMethod = v),
            ),
            const SizedBox(height: 10),
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
              const SizedBox(height: 20),
              const Text('Mobile Money Details',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedNetwork,
                decoration: InputDecoration(
                  labelText: 'Network',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                items: _networks.map((n) => DropdownMenuItem(value: n, child: Text(n))).toList(),
                onChanged: (v) => setState(() => _selectedNetwork = v!),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _mobileNumberCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Mobile Number',
                  hintText: '077XXXXXXX',
                  prefixIcon: const Icon(Icons.phone_rounded),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],

            // COD notice
            if (_selectedMethod == 'cash_on_delivery') ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Colors.orange),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'You will pay the stylist directly in cash when the service is done. Please have the exact amount ready.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 32),

            // Pay button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _processing ? null : _processPayment,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: _processing
                    ? const SizedBox(height: 22, width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : Text(
                        _selectedMethod == 'cash_on_delivery'
                            ? 'Confirm Booking (Pay Later)'
                            : 'Pay \$${_amount.toStringAsFixed(2)}',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 16),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w500,
                  color: valueColor ?? Colors.black87)),
        ],
      ),
    );
  }
}