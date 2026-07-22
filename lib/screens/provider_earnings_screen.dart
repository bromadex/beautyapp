import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ProviderEarningsScreen extends StatefulWidget {
  const ProviderEarningsScreen({super.key});

  @override
  State<ProviderEarningsScreen> createState() => _ProviderEarningsScreenState();
}

class _ProviderEarningsScreenState extends State<ProviderEarningsScreen> {
  List<Map<String, dynamic>> _payments = [];
  bool _loading = true;

  // Providers keep 100% of every booking payment — no commission
  double get _totalEarnings =>
      _payments.where((p) => p['status'] == 'paid').fold(
          0.0, (sum, p) => sum + (p['amount'] as num).toDouble());

  double get _pendingCod =>
      _payments.where((p) => p['status'] == 'pending').fold(
          0.0, (sum, p) => sum + (p['amount'] as num).toDouble());

  int get _totalTransactions => _payments.length;

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
        SnackBar(
          content: const Text('Cash payment recorded'),
          backgroundColor: AppColors.success,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
    }
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

    return Scaffold(
      appBar: AppBar(title: const Text('My Earnings')),
      body: Column(
        children: [
          // Dashboard summary cards
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: _DashboardCard(
                    label: 'Total Earned',
                    amount: '\$${_totalEarnings.toStringAsFixed(2)}',
                    icon: Icons.account_balance_wallet_rounded,
                    color: AppColors.success,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _DashboardCard(
                    label: 'COD Pending',
                    amount: '\$${_pendingCod.toStringAsFixed(2)}',
                    icon: Icons.hourglass_bottom_rounded,
                    color: AppColors.warning,
                  ),
                ),
              ],
            ),
          ),

          // No-commission banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                    color: AppColors.success.withValues(alpha: 0.2)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.verified_rounded,
                      color: AppColors.success, size: 18),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      'You keep 100% of what you earn — no hidden fees, no commission.',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.success),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Transactions count
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Text(
                  'Recent Transactions',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalTransactions total',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Payments list
          Expanded(
            child: _payments.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 40,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.lg),
                        Text(
                          'No payments yet',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Your earnings will appear here',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    itemCount: _payments.length,
                    itemBuilder: (_, i) {
                      final p = _payments[i];
                      final clientName =
                          p['client']?['full_name'] ?? 'Client';
                      final isCodPending = p['status'] == 'pending' &&
                          p['method'] == 'cash_on_delivery';

                      return Container(
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        padding: AppSpacing.cardPadding,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadius.lgAll,
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header row
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.spaceBetween,
                              children: [
                                Expanded(
                                  child: Text(
                                    clientName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                      color: AppColors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                _StatusChip(status: p['status']),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.md),

                            // Payment details row
                            Row(
                              children: [
                                _PaymentDetail(
                                  label: 'You Receive',
                                  value:
                                      '\$${(p['amount'] as num).toStringAsFixed(2)}',
                                  valueColor: AppColors.success,
                                  bold: true,
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                _PaymentDetail(
                                  label: 'Method',
                                  value: _methodLabel(p['method']),
                                ),
                              ],
                            ),

                            if (p['transaction_ref'] != null) ...[
                              const SizedBox(height: AppSpacing.sm),
                              Text(
                                'Ref: ${p['transaction_ref']}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textTertiary,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],

                            if (isCodPending) ...[
                              const SizedBox(height: AppSpacing.md),
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: () =>
                                      _markCodPaid(p['id'], p['booking_id']),
                                  icon: const Icon(Icons.check_rounded,
                                      size: 18),
                                  label:
                                      const Text('Mark Cash as Received'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: AppColors.success,
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                  ),
                                ),
                              ),
                            ],
                          ],
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
      case 'card':
        return 'Card';
      case 'mobile_money':
        return 'Mobile Money';
      case 'cash_on_delivery':
        return 'Cash';
      default:
        return method;
    }
  }
}

// -- Dashboard summary card ---------------------------------------------------

class _DashboardCard extends StatelessWidget {
  final String label;
  final String amount;
  final IconData icon;
  final Color color;

  const _DashboardCard({
    required this.label,
    required this.amount,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: AppSpacing.cardPadding,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            amount,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// -- Status chip --------------------------------------------------------------

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    Color bgColor;
    Color fgColor;
    String label;
    switch (status) {
      case 'paid':
        fgColor = AppColors.success;
        bgColor = AppColors.success.withValues(alpha: 0.1);
        label = 'Paid';
        break;
      case 'pending':
        fgColor = AppColors.warning;
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        label = 'COD Pending';
        break;
      case 'refunded':
        fgColor = AppColors.error;
        bgColor = AppColors.error.withValues(alpha: 0.1);
        label = 'Refunded';
        break;
      default:
        fgColor = AppColors.textTertiary;
        bgColor = Colors.grey.withValues(alpha: 0.1);
        label = status;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fgColor,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// -- Payment detail -----------------------------------------------------------

class _PaymentDetail extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final bool bold;
  const _PaymentDetail({
    required this.label,
    required this.value,
    this.valueColor,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textTertiary,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
            color: valueColor ?? AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
