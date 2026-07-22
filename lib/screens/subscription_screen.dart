import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/paynow_service.dart';
import '../supabase_client.dart';
import '../theme.dart';

/// Provider subscription — flat pricing, zero commission.
///
/// The model:
///  - Create profile, get browsed & messaged → FREE
///  - Accepting bookings requires activation: $3 (includes first month)
///  - After month 1 → $5/month
///  - Providers keep 100% of booking payments — no commission
///  - Cancel anytime → profile hidden; reactivate later for $3
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  bool _loading = true;
  bool _processing = false;
  String? _error;

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
      final data = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _subscription = data;
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

  bool get _isActive {
    if (_subscription == null) return false;
    if (_subscription!['status'] != 'active') return false;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    return end != null && end.isAfter(DateTime.now());
  }

  /// True for lapsed or cancelled subscribers (reactivation costs $3 again).
  bool get _isLapsed => _subscription != null && !_isActive;

  int get _daysRemaining {
    final end = DateTime.tryParse(_subscription?['end_date'] ?? '');
    if (end == null) return 0;
    return end.difference(DateTime.now()).inDays.clamp(0, 9999);
  }

  /// Activation ($3, first month) applies to new and lapsed providers.
  /// Renewal ($5/month) applies while active.
  bool get _payingActivation => !_isActive;

  double get _price => _payingActivation
      ? AppConfig.providerActivationFee
      : AppConfig.providerMonthlyFee;

  Future<void> _pay() async {
    setState(() => _processing = true);

    // Real Paynow checkout when configured
    final outcome = await PaynowCheckout.run(
      context,
      purpose: 'subscription',
      tier: _payingActivation ? 'activation' : 'monthly',
      months: 1,
    );
    if (outcome != PaynowOutcome.unconfigured) {
      if (mounted) setState(() => _processing = false);
      if (outcome == PaynowOutcome.paid) {
        await _load();
        if (mounted) _snack('Payment received — you\'re live!', AppColors.success);
      } else if (mounted &&
          (outcome == PaynowOutcome.failed || outcome == PaynowOutcome.timeout)) {
        _snack(
            outcome == PaynowOutcome.failed
                ? 'Payment was not completed. Please try again.'
                : 'Payment still pending — refresh this page in a few minutes.',
            AppColors.warning);
      }
      return;
    }

    // Simulated fallback until Paynow is configured
    try {
      final userId = supabase.auth.currentUser!.id;
      final start = DateTime.now();

      // Renewals extend from the current end date, activations start today
      DateTime base = start;
      if (!_payingActivation) {
        final end = DateTime.tryParse(_subscription?['end_date'] ?? '');
        if (end != null && end.isAfter(start)) base = end;
      }
      final endDate = DateTime(base.year, base.month + 1, base.day);

      final payload = {
        'provider_id': userId,
        'start_date': start.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'status': 'active',
        'plan': _payingActivation ? 'activation' : 'monthly',
        'amount_paid': _price,
        'payment_ref': 'SIM-${DateTime.now().millisecondsSinceEpoch}',
      };

      if (_subscription == null) {
        await supabase.from('subscriptions').insert(payload);
      } else {
        await supabase
            .from('subscriptions')
            .update(payload)
            .eq('provider_id', userId);
      }

      await supabase
          .from('provider_profiles')
          .update({'is_hidden': false}).eq('provider_id', userId);

      await _load();
      if (mounted) {
        _snack(
            _payingActivation
                ? 'Account activated — your first month is live!'
                : 'Renewed for another month!',
            AppColors.success);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _cancel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.pause_circle_outline_rounded,
              color: AppColors.warning, size: 32),
        ),
        title: const Text('Cancel Subscription?'),
        content: const Text(
            'Your profile will be hidden from search and you won\'t be able to accept bookings. You can reactivate anytime for \$3.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep It')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Subscription'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _processing = true);
    try {
      final userId = supabase.auth.currentUser!.id;
      await supabase
          .from('subscriptions')
          .update({'status': 'cancelled'}).eq('provider_id', userId);
      await supabase
          .from('provider_profiles')
          .update({'is_hidden': true}).eq('provider_id', userId);
      await _load();
      if (mounted) {
        _snack('Subscription cancelled — reactivate anytime for \$3.',
            AppColors.warning);
      }
    } catch (e) {
      if (mounted) _snack('Error: $e', AppColors.error);
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: Center(
          child: Padding(
            padding: AppSpacing.screenPadding,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline_rounded,
                    size: 48, color: AppColors.error),
                const SizedBox(height: AppSpacing.lg),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xl),
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

    return Scaffold(
      appBar: AppBar(title: const Text('Subscription')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildStatusCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildPricingCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildBenefits(),
                const SizedBox(height: AppSpacing.xl),
                _buildInfoBox(),
                const SizedBox(height: AppSpacing.xl),
                _buildPayButton(),
                if (_isActive) ...[
                  const SizedBox(height: AppSpacing.md),
                  TextButton(
                    onPressed: _processing ? null : _cancel,
                    child: const Text('Cancel subscription',
                        style: TextStyle(color: AppColors.textTertiary)),
                  ),
                ],
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    late final List<Color> gradient;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    if (_isActive) {
      gradient = const [Color(0xFFC2185B), Color(0xFF880E4F)];
      icon = Icons.verified_rounded;
      title = 'Subscription Active';
      subtitle =
          '$_daysRemaining days remaining · you keep 100% of what you earn';
    } else if (_subscription?['status'] == 'cancelled') {
      gradient = const [Color(0xFF6B7280), Color(0xFF4B5563)];
      icon = Icons.pause_circle_outline_rounded;
      title = 'Subscription Cancelled';
      subtitle =
          'Your profile is hidden. Reactivate for \$${AppConfig.providerActivationFee.toStringAsFixed(0)} to go live again.';
    } else if (_isLapsed) {
      gradient = const [Color(0xFFDC2626), Color(0xFFEF4444)];
      icon = Icons.warning_rounded;
      title = 'Subscription Expired';
      subtitle =
          'Reactivate for \$${AppConfig.providerActivationFee.toStringAsFixed(0)} to keep accepting bookings.';
    } else {
      gradient = const [Color(0xFF6B7280), Color(0xFF4B5563)];
      icon = Icons.spa_rounded;
      title = 'Not Activated Yet';
      subtitle =
          'Clients can find and message you for free. Activate to start accepting bookings.';
    }

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
            colors: gradient,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight),
        borderRadius: AppRadius.xlAll,
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: AppRadius.mdAll,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 16)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontSize: 12.5,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPricingCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const Text('Simple, Honest Pricing',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: _priceBlock(
                  highlight: _payingActivation,
                  amount: '\$3',
                  label: 'First month',
                  sub: 'One-time activation,\nmonth 1 included',
                ),
              ),
              const Icon(Icons.arrow_forward_rounded,
                  color: AppColors.textTertiary, size: 20),
              Expanded(
                child: _priceBlock(
                  highlight: !_payingActivation,
                  amount: '\$5',
                  label: 'Per month after',
                  sub: 'Cancel anytime,\nno lock-in',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: const Text('NO HIDDEN FEES · NO COMMISSION',
                style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                    color: AppColors.success)),
          ),
        ],
      ),
    );
  }

  Widget _priceBlock({
    required bool highlight,
    required String amount,
    required String label,
    required String sub,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg, horizontal: AppSpacing.sm),
      decoration: BoxDecoration(
        color: highlight
            ? AppColors.primary.withValues(alpha: 0.06)
            : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        border: highlight
            ? Border.all(color: AppColors.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Column(
        children: [
          Text(amount,
              style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  height: 1,
                  color: highlight ? AppColors.primary : AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.xs),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 2),
          Text(sub,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 10.5, color: AppColors.textTertiary, height: 1.3)),
        ],
      ),
    );
  }

  Widget _buildBenefits() {
    const benefits = [
      ('You keep 100% of what you earn', Icons.account_balance_wallet_rounded),
      ('Unlimited bookings', Icons.all_inclusive_rounded),
      ('Appear in client searches', Icons.search_rounded),
      ('Gallery, promos, reviews & ratings', Icons.auto_awesome_rounded),
      ('Cancel anytime — reactivate for \$3', Icons.lock_open_rounded),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('What you get',
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          ...benefits.map((b) => Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 13, color: AppColors.success),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(b.$1,
                          style: const TextStyle(
                              fontSize: 14, color: AppColors.textPrimary)),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildInfoBox() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.info, size: 18),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'The \$3 activation keeps BeauTap free of fake profiles and bots — every stylist on the platform is real and invested. Pay securely via EcoCash, mobile money, or card through Paynow.',
              style: TextStyle(fontSize: 12, color: AppColors.info, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPayButton() {
    final label = _processing
        ? 'Processing...'
        : _payingActivation
            ? (_isLapsed
                ? 'Reactivate — \$${AppConfig.providerActivationFee.toStringAsFixed(0)}'
                : 'Activate — \$${AppConfig.providerActivationFee.toStringAsFixed(0)} (first month included)')
            : 'Renew — \$${AppConfig.providerMonthlyFee.toStringAsFixed(0)} for 1 month';

    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: AppRadius.mdAll,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: _processing ? null : _pay,
        icon: _processing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.rocket_launch_rounded),
        label: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
    );
  }
}
