import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

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

  static const _plans = [
    {'label': '1 Month',  'months': 1,  'price': 10.00},
    {'label': '3 Months', 'months': 3,  'price': 27.00},
    {'label': '6 Months', 'months': 6,  'price': 50.00},
  ];

  int _selectedPlan = 0;

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
      final userId = supabase.auth.currentUser!.id;

      final data = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _subscription = data;
          _loading = false;
        });
      }
    } catch (e) {
      print('Error loading subscription: $e');
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

  int get _daysRemaining {
    if (_subscription == null) return 0;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    if (end == null) return 0;
    final diff = end.difference(DateTime.now()).inDays;
    return diff.clamp(0, 9999);
  }

  Future<void> _subscribe() async {
    setState(() => _processing = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final plan = _plans[_selectedPlan];
      final months = plan['months'] as int;
      final price = plan['price'] as double;

      final startDate = DateTime.now();
      final endDate = DateTime(startDate.year, startDate.month + months, startDate.day);

      final payload = {
        'provider_id': userId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'status': 'active',
        'plan': '${months}_month',
        'amount_paid': price,
        'payment_ref': 'SIM-${DateTime.now().millisecondsSinceEpoch}',
      };

      final existing = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('subscriptions').insert(payload);
      } else {
        await supabase.from('subscriptions').update(payload).eq('provider_id', userId);
      }

      await supabase
          .from('provider_profiles')
          .update({'is_hidden': false})
          .eq('provider_id', userId);

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription activated for $months month(s)'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
      print('Subscribe error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _debugExpire() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await supabase.from('subscriptions').update({
        'end_date': yesterday.toIso8601String().split('T')[0],
        'status': 'expired',
      }).eq('provider_id', userId);

      await supabase.from('provider_profiles')
          .update({'is_hidden': true})
          .eq('provider_id', userId);

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('DEBUG: Subscription expired & profile hidden'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
      print('Debug expire error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Subscription')),
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
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
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.error_outline_rounded,
                      size: 48, color: AppColors.error),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text(
                  'Something went wrong',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxl),
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
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status card
            _buildStatusCard(),
            const SizedBox(height: AppSpacing.xxxl),

            // Plan selector header
            Text(
              _isActive ? 'Renew / Upgrade Plan' : 'Choose a Plan',
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
                letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Unlock visibility and start accepting bookings',
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),

            // Plan cards
            ..._plans.asMap().entries.map((entry) {
              final i = entry.key;
              final plan = entry.value;
              return _buildPlanCard(i, plan);
            }),

            const SizedBox(height: AppSpacing.lg),

            // Features list
            _buildFeaturesList(),

            const SizedBox(height: AppSpacing.xl),

            // Info box
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: AppColors.info.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded,
                      color: AppColors.info, size: 18),
                  const SizedBox(width: AppSpacing.md),
                  const Expanded(
                    child: Text(
                      'Payment is simulated for now. Real payment integration (PayStack/Stripe) comes in Stage 8.',
                      style: TextStyle(fontSize: 12, color: AppColors.info),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Subscribe button
            _buildSubscribeButton(),

            const SizedBox(height: AppSpacing.xxxl),

            // Debug tools
            Divider(color: Colors.grey.shade200),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'Debug Tools (remove before production)',
              style: TextStyle(
                color: AppColors.textTertiary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            OutlinedButton.icon(
              onPressed: _debugExpire,
              icon: Icon(Icons.timer_off_outlined,
                  color: AppColors.warning, size: 18),
              label: Text('Simulate Expiry',
                  style: TextStyle(color: AppColors.warning)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.warning.withValues(alpha: 0.5)),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    if (_subscription == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.grey.shade100,
              Colors.grey.shade50,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: AppRadius.xlAll,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 12,
                  ),
                ],
              ),
              child: const Icon(Icons.lock_outline_rounded,
                  size: 32, color: AppColors.textTertiary),
            ),
            const SizedBox(height: AppSpacing.lg),
            const Text(
              'No Active Subscription',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 18,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Subscribe to appear in client searches\nand start accepting bookings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
                height: 1.5,
              ),
            ),
          ],
        ),
      );
    }

    final endDate = DateTime.tryParse(_subscription!['end_date'] ?? '');
    final endStr = endDate != null
        ? '${endDate.day}/${endDate.month}/${endDate.year}'
        : 'Unknown';

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: _isActive
            ? const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : const LinearGradient(
                colors: [Color(0xFFDC2626), Color(0xFFEF4444)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
        borderRadius: AppRadius.xlAll,
        boxShadow: [
          BoxShadow(
            color: (_isActive ? AppColors.success : AppColors.error)
                .withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                _isActive ? Icons.verified_rounded : Icons.warning_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              _isActive ? 'Subscription Active' : 'Subscription Expired',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 16,
              ),
            ),
          ]),
          const SizedBox(height: AppSpacing.xl),
          if (_isActive) ...[
            Text(
              '$_daysRemaining',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 48,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'days remaining',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'Expires $endStr',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ] else ...[
            Text(
              'Expired on $endStr',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Your profile is hidden from clients. Renew to restore visibility.',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlanCard(int index, Map<String, dynamic> plan) {
    final isSelected = _selectedPlan == index;
    final months = plan['months'] as int;
    final price = plan['price'] as double;
    final perMonth = (price / months).toStringAsFixed(2);

    String? badgeText;
    Color? badgeColor;
    if (months == 3) {
      badgeText = 'Save 10%';
      badgeColor = AppColors.success;
    } else if (months == 6) {
      badgeText = 'Best Value';
      badgeColor = AppColors.secondary;
    }

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withValues(alpha: 0.04)
              : AppColors.cardLight,
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: AppRadius.lgAll,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            // Radio indicator
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? AppColors.primary : Colors.grey.shade300,
                  width: isSelected ? 2 : 1.5,
                ),
                color: isSelected ? AppColors.primary : Colors.transparent,
              ),
              child: isSelected
                  ? const Icon(Icons.check_rounded,
                      size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: AppSpacing.lg),

            // Plan details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    plan['label'] as String,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      color: isSelected
                          ? AppColors.textPrimary
                          : AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '\$$perMonth / month',
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

            // Badge
            if (badgeText != null) ...[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: badgeColor!.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  badgeText,
                  style: TextStyle(
                    color: badgeColor,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
            ],

            // Price
            Text(
              '\$${price.toStringAsFixed(2)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: isSelected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturesList() {
    const features = [
      'Appear in client search results',
      'Accept and manage bookings',
      'Showcase your gallery portfolio',
      'Receive client reviews and ratings',
      'Priority customer support',
    ];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'What you get',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          ...features.map((feature) => Padding(
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
                Text(
                  feature,
                  style: const TextStyle(
                    fontSize: 14,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildSubscribeButton() {
    final selectedPrice =
        (_plans[_selectedPlan]['price'] as double).toStringAsFixed(2);

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
        onPressed: _processing ? null : _subscribe,
        icon: _processing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : const Icon(Icons.diamond_outlined),
        label: Text(
          _processing
              ? 'Processing...'
              : _isActive
                  ? 'Renew Subscription -- \$$selectedPrice'
                  : 'Subscribe Now -- \$$selectedPrice',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      ),
    );
  }
}
