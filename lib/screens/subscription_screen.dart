import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../config/app_config.dart';
import 'package:go_router/go_router.dart';
import '../services/fee_checkout.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

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
  Map<String, dynamic>? _plan;
  Map<String, dynamic>? _salon;
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
      final plan = await supabase.rpc('my_plan');
      final salon = await supabase.rpc('my_salon');
      if (mounted) {
        setState(() {
          _subscription = data;
          _plan = Map<String, dynamic>.from(plan as Map);
          _salon = salon == null ? null : Map<String, dynamic>.from(salon as Map);
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

  /// Covered by the salon owner's plan rather than their own.
  bool get _viaSalon => _plan?['via_salon'] == true;
  bool get _onSalonPlan => _plan?['own_plan'] == 'salon';
  bool get _ownsSalon => _salon?['is_owner'] == true;
  List get _pendingClaims => (_plan?['fee_claims'] as List?) ?? const [];

  bool get _isActive {
    if (_viaSalon) return true;
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


  Future<void> _payFee(BeauTapFee fee, String doneMessage) async {
    setState(() => _processing = true);
    final outcome = await FeeCheckout.run(context, fee);
    if (mounted) setState(() => _processing = false);
    if (outcome == FeeOutcome.cancelled) return;
    await _load();
    if (!mounted) return;
    _snack(
      outcome == FeeOutcome.paid ? doneMessage : 'Thanks! We\'ll switch it on as soon as we see your EcoCash payment.',
      outcome == FeeOutcome.paid ? AppColors.success : AppColors.info,
    );
  }

  Future<void> _pay() => _payFee(
      BeauTapFee('subscription', _payingActivation ? 'activation' : 'monthly'), 'Payment received. You\'re Pro!');

  Future<void> _buyFeatured() => _payFee(const BeauTapFee('featured'), 'You\'re featured for the next 7 days!');

  Future<void> _paySalon() => _payFee(const BeauTapFee('subscription', 'salon'), 'Salon plan active for your whole team!');

  Widget _buildPendingClaims() {
    return Column(children: [
      for (final c in _pendingClaims)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: SoftBanner(
            icon: TablerIcons.clock_hour_4,
            color: AppColors.warning,
            title: 'Checking your EcoCash payment',
            message: '\$${(c['amount'] as num).toStringAsFixed(0)} · ref ${c['reference']}. '
                'We\'ll notify you as soon as it\'s confirmed.',
          ),
        ),
    ]);
  }

  Widget _buildSalonCard() {
    final s = _salon;
    if (s == null) {
      return InkWell(
        onTap: () => context.push('/provider/salon').then((_) => _load()),
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: const Row(children: [
            Icon(TablerIcons.building_store, color: AppColors.primary),
            SizedBox(width: 12),
            Expanded(
              child: Text('Run a salon? One \$15 plan covers you and up to 7 staff.',
                  style: TextStyle(fontWeight: FontWeight.w600)),
            ),
            Icon(TablerIcons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      );
    }
    if (!_ownsSalon) return const SizedBox.shrink();
    final until = DateTime.tryParse((s['plan_until'] ?? '').toString());
    final active = s['plan_active'] == true;
    final people = (s['members'] as List?)?.length ?? 1;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.primarySoft,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(TablerIcons.building_store, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Salon plan · ${s['name']}', style: Theme.of(context).textTheme.titleMedium)),
          const Text('\$15 / month', style: TextStyle(fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 6),
        Text(
          active && until != null
              ? 'Active until ${until.day}/${until.month}. Covers the first 8 people in your salon ($people now).'
              : 'Covers you and up to 7 staff ($people in your salon now). Anyone past 8 needs their own Pro plan.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _processing ? null : _paySalon,
          child: Text(active ? 'Add another month' : 'Pay salon plan'),
        ),
      ]),
    );
  }

  Widget _buildFreeUsage() {
    final used = (_plan?['free_used'] as num?)?.toInt() ?? 0;
    final limit = (_plan?['free_limit'] as num?)?.toInt() ?? 5;
    final left = (limit - used).clamp(0, limit);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Pill(label: 'FREE PLAN', color: AppColors.info),
            const Spacer(),
            Text('$used of $limit bookings this month', style: Theme.of(context).textTheme.labelMedium),
          ]),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: AppRadius.pill,
            child: LinearProgressIndicator(
              value: limit == 0 ? 1 : used / limit,
              minHeight: 8,
              color: left == 0 ? AppColors.error : AppColors.primary,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            left == 0
                ? 'You\'ve used this month\'s free bookings. Go Pro to keep accepting clients.'
                : '$left free booking${left == 1 ? '' : 's'} left this month. Pro removes the limit.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
          ),
        ]),
      ),
    );
  }

  Widget _buildFeaturedCard() {
    final until = DateTime.tryParse((_plan?['featured_until'] ?? '').toString())?.toLocal();
    final active = until != null && until.isAfter(DateTime.now());
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.secondary.withValues(alpha: 0.1),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.secondary.withValues(alpha: 0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(TablerIcons.star_filled, color: AppColors.secondary),
          const SizedBox(width: 8),
          Text('Get featured', style: Theme.of(context).textTheme.titleMedium),
          const Spacer(),
          const Text('\$3 / 7 days', style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 6),
        Text(
          active
              ? 'You\'re featured until ${until.day}/${until.month}. Buying again adds another 7 days.'
              : 'Appear at the top of Browse and Home in your city, with a Featured badge.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: _processing ? null : _buyFeatured,
          child: Text(active ? 'Add 7 more days' : 'Feature my profile'),
        ),
      ]),
    );
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
          child: const Icon(TablerIcons.player_pause,
              color: AppColors.warning, size: 32),
        ),
        title: const Text('Cancel Subscription?'),
        content: const Text(
            'You\'ll move to the Free plan (5 bookings a month). You can go Pro again anytime.'),
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
      await supabase.rpc('cancel_my_subscription');
      await _load();
      if (mounted) {
        _snack('You\'re on the Free plan now.',
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
                const Icon(TablerIcons.alert_circle,
                    size: 48, color: AppColors.error),
                const SizedBox(height: AppSpacing.lg),
                Text(_error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 13, color: AppColors.textSecondary)),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  onPressed: _load,
                  icon: const Icon(TablerIcons.refresh),
                  label: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Your plan')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_pendingClaims.isNotEmpty) _buildPendingClaims(),
                _buildStatusCard(),
                if (!_isActive) ...[
                  const SizedBox(height: AppSpacing.md),
                  _buildFreeUsage(),
                ],
                const SizedBox(height: AppSpacing.xl),
                _buildPricingCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildBenefits(),
                const SizedBox(height: AppSpacing.xl),
                _buildInfoBox(),
                const SizedBox(height: AppSpacing.xl),
                if (!_viaSalon && !_onSalonPlan) _buildPayButton(),
                const SizedBox(height: AppSpacing.xl),
                _buildSalonCard(),
                const SizedBox(height: AppSpacing.xl),
                _buildFeaturedCard(),
                if (_isActive && !_viaSalon) ...[
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

    if (_viaSalon) {
      gradient = const [AppColors.primary, AppColors.primaryDark];
      icon = TablerIcons.building_store;
      title = 'Pro through ${_salon?['name'] ?? 'your salon'}';
      subtitle = 'Your salon\'s plan covers you. No need to pay yourself.';
    } else if (_isActive) {
      gradient = const [AppColors.primary, AppColors.primaryDark];
      icon = TablerIcons.rosette_discount_check;
      title = 'Pro — active';
      subtitle =
          '$_daysRemaining days remaining · you keep 100% of what you earn';
    } else if (_subscription?['status'] == 'cancelled') {
      gradient = const [AppColors.pine, AppColors.primaryDark];
      icon = TablerIcons.player_pause;
      title = 'Pro cancelled';
      subtitle =
          'You\'re on the Free plan. Go Pro again for \$${AppConfig.providerActivationFee.toStringAsFixed(0)} to remove the booking limit.';
    } else if (_isLapsed) {
      gradient = const [AppColors.error, AppColors.errorText];
      icon = TablerIcons.alert_triangle;
      title = 'Pro expired';
      subtitle =
          'You\'re on the Free plan (5 bookings a month). Renew Pro to remove the limit.';
    } else {
      gradient = const [AppColors.pine, AppColors.primaryDark];
      icon = TablerIcons.leaf;
      title = 'You\'re on the Free plan';
      subtitle =
          'Take up to 5 bookings a month for free. Go Pro for unlimited bookings.';
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
              const Icon(TablerIcons.arrow_right,
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
      ('You keep 100% of what you earn', TablerIcons.wallet),
      ('Unlimited bookings (Free plan: 5 a month)', TablerIcons.infinity),
      ('Appear in client searches', TablerIcons.search),
      ('Gallery, promos, reviews & ratings', TablerIcons.sparkles),
      ('Cancel anytime — you keep the Free plan', TablerIcons.lock_open),
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
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
                      child: const Icon(TablerIcons.check,
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
          Icon(TablerIcons.info_circle, color: AppColors.info, size: 18),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'The \$3 activation keeps BeauTap free of fake profiles and bots — every pro on the platform is real and invested. Pay securely via EcoCash, mobile money, or card through Paynow.',
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
            : const Icon(TablerIcons.rocket),
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
