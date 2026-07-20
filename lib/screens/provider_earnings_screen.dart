import 'package:flutter/material.dart';
import '../supabase_client.dart';

class ProviderEarningsScreen extends StatefulWidget {
  const ProviderEarningsScreen({super.key});

  @override
  State<ProviderEarningsScreen> createState() => _ProviderEarningsScreenState();
}

class _ProviderEarningsScreenState extends State<ProviderEarningsScreen> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  double get _totalEarnings =>
      _payments.where((p) => p['status'] == 'paid').fold(
          0.0, (sum, p) => sum + (p['provider_earnings'] as num).toDouble());

  double get _pendingCod =>
      _payments.where((p) => p['status'] == 'pending').fold(
          0.0, (sum, p) => sum + (p['provider_earnings'] as num).toDouble());

  @override
  void initState() {
    super.initState();
    _loadEarnings();
  }

  Future<void> _loadEarnings() async {
    final uid = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('payments')
        .select('*, bookings(booking_time, status), client:profiles!payments_client_id_fkey(full_name)')
        .eq('provider_id', uid)
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _payments = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<void> _markCodPaid(String paymentId, String bookingId) async {
    await supabase.from('payments').update({
      'status': 'paid',
      'paid_at': DateTime.now().toIso8601String(),
    }).eq('id', paymentId);

    await supabase.from('bookings').update({
      'payment_status': 'paid',
      'status': 'completed',
    }).eq('id', bookingId);

    await _loadEarnings();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('✅ Cash payment recorded')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Earnings')),
      body: Column(
        children: [
          // Summary cards
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: _EarningCard(
                    label: 'Total Earned',
                    amount: _totalEarnings,
                    color: Colors.green,
                    icon: Icons.account_balance_wallet_rounded,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _EarningCard(
                    label: 'COD Pending',
                    amount: _pendingCod,
                    color: Colors.orange,
                    icon: Icons.hourglass_bottom_rounded,
                  ),
                ),
              ],
            ),
          ),

          // Payments list
          Expanded(
            child: _payments.isEmpty
                ? const Center(child: Text('No payments yet'))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _payments.length,
                    itemBuilder: (_, i) {
                      final p = _payments[i];
                      final clientName = p['client']?['full_name'] ?? 'Client';
                      final isCodPending = p['status'] == 'pending' &&
                          p['method'] == 'cash_on_delivery';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(clientName,
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                  _StatusChip(status: p['status']),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  _PaymentDetail(
                                      label: 'Total',
                                      value: '\$${(p['amount'] as num).toStringAsFixed(2)}'),
                                  const SizedBox(width: 16),
                                  _PaymentDetail(
                                      label: 'Your Cut',
                                      value: '\$${(p['provider_earnings'] as num).toStringAsFixed(2)}',
                                      bold: true),
                                  const SizedBox(width: 16),
                                  _PaymentDetail(
                                      label: 'Method',
                                      value: _methodLabel(p['method'])),
                                ],
                              ),
                              if (p['transaction_ref'] != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Ref: ${p['transaction_ref']}',
                                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace'),
                                ),
                              ],
                              if (isCodPending) ...[
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: () => _markCodPaid(p['id'], p['booking_id']),
                                    icon: const Icon(Icons.check_rounded),
                                    label: const Text('Mark Cash as Received'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'card': return 'Card';
      case 'mobile_money': return 'Mobile Money';
      case 'cash_on_delivery': return 'Cash';
      default: return method;
    }
  }
}

class _EarningCard extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final IconData icon;

  const _EarningCard({
    required this.label,
    required this.amount,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text('\$${amount.toStringAsFixed(2)}',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'paid':
        color = Colors.green; label = 'Paid'; break;
      case 'pending':
        color = Colors.orange; label = 'COD Pending'; break;
      case 'refunded':
        color = Colors.red; label = 'Refunded'; break;
      default:
        color = Colors.grey; label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
    );
  }
}

class _PaymentDetail extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _PaymentDetail({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
        Text(value,
            style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
      ],
    );
  }
}