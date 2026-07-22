import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../services/paynow_service.dart';
import '../supabase_client.dart';
import '../theme.dart';

/// Stage 21: Subscription Revamp — First Booking Free.
///
/// Tiers:
///  - New (free): profile visible, messaging, accept 1st booking
///  - Active ($10/mo): unlimited bookings + gallery + promos
///  - Featured ($25/mo): top-3 search placement per area (limited slots)
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _waitlistEntry;
  int _featuredInArea = 0;
  bool _loading = true;
  bool _processing = false;
  String? _error;

  static const int maxFeaturedPerArea = 3;

  // tier -> months -> price
  static const _pricing = {
    'active': [
      {'label': '1 Month', 'months': 1, 'price': 10.00},
      {'label': '3 Months', 'months': 3, 'price': 27.00},
      {'label': '6 Months', 'months': 6, 'price': 50.00},
    ],
    'featured': [
      {'label': '1 Month', 'months': 1, 'price': 25.00},
      {'label': '3 Months', 'months': 3, 'price': 67.00},
      {'label': '6 Months', 'months': 6, 'price': 125.00},
    ],
  };

  String _selectedTier = 'active';
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

      final sub = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();

      Map<String, dynamic>? profile;
      try {
        profile = await supabase
            .from('provider_profiles')
            .select('first_booking_used, latitude, longitude, service_radius_km')
            .eq('provider_id', userId)
            .maybeSingle();
      } catch (_) {
        // Migration not run yet — fall back to legacy columns
        profile = await supabase
            .from('provider_profiles')
            .select('latitude, longitude')
            .eq('provider_id', userId)
            .maybeSingle();
      }

      Map<String, dynamic>? waitlist;
      int featuredCount = 0;
      try {
        waitlist = await supabase
            .from('featured_waitlist')
            .select()
            .eq('provider_id', userId)
            .eq('status', 'waiting')
            .maybeSingle();
        featuredCount = await _countFeaturedInArea(profile);
      } catch (_) {
        // featured_waitlist / tier column not migrated yet
      }

      if (mounted) {
        setState(() {
          _subscription = sub;
          _providerProfile = profile;
          _waitlistEntry = waitlist;
          _featuredInArea = featuredCount;
          if (_isActive && _subscription!['tier'] == 'featured') {
            _selectedTier = 'featured';
          }
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

  /// Counts active Featured providers whose location falls inside my
  /// service area (my radius, default 10km). Area = provider's service
  /// radius per the roadmap.
  Future<int> _countFeaturedInArea(Map<String, dynamic>? myProfile) async {
    final myLat = (myProfile?['latitude'] as num?)?.toDouble();
    final myLng = (myProfile?['longitude'] as num?)?.toDouble();
    final myRadius =
        (myProfile?['service_radius_km'] as num?)?.toDouble() ?? 10.0;

    final userId = supabase.auth.currentUser!.id;
    final subs = await supabase
        .from('subscriptions')
        .select('provider_id, status, end_date, tier')
        .eq('tier', 'featured')
        .eq('status', 'active');

    final now = DateTime.now();
    final featuredIds = <String>[];
    for (final s in subs) {
      if (s['provider_id'] == userId) continue;
      final end = DateTime.tryParse(s['end_date'] ?? '');
      if (end != null && end.isAfter(now)) {
        featuredIds.add(s['provider_id'] as String);
      }
    }
    if (featuredIds.isEmpty) return 0;
    // Without my location, treat every featured provider as in-area (safe).
    if (myLat == null || myLng == null) return featuredIds.length;

    final profiles = await supabase
        .from('provider_profiles')
        .select('provider_id, latitude, longitude')
        .inFilter('provider_id', featuredIds);

    var count = 0;
    for (final p in profiles) {
      final lat = (p['latitude'] as num?)?.toDouble();
      final lng = (p['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) {
        count++; // unknown location competes for the area slot
        continue;
      }
      if (_haversineKm(myLat, myLng, lat, lng) <= myRadius) count++;
    }
    return count;
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180;

  bool get _isActive {
    if (_subscription == null) return false;
    if (_subscription!['status'] != 'active') return false;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    return end != null && end.isAfter(DateTime.now());
  }

  String get _currentTier {
    if (!_isActive) return 'new';
    return (_subscription!['tier'] as String?) ?? 'active';
  }

  bool get _firstBookingUsed => _providerProfile?['first_booking_used'] == true;

  bool get _featuredSlotsFull => _featuredInArea >= maxFeaturedPerArea;

  int get _daysRemaining {
    if (_subscription == null) return 0;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    if (end == null) return 0;
    return end.difference(DateTime.now()).inDays.clamp(0, 9999);
  }

  Future<void> _joinWaitlist() async {
    setState(() => _processing = true);
    try {
      await supabase.from('featured_waitlist').upsert(
        {
          'provider_id': supabase.auth.currentUser!.id,
          'status': 'waiting',
          'requested_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'provider_id',
      );
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                "You're on the Featured waitlist. We'll notify you when a slot opens in your area."),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Could not join waitlist: $e'),
              backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _subscribe() async {
    // Featured with all area slots taken → waitlist instead of payment
    if (_selectedTier == 'featured' &&
        _featuredSlotsFull &&
        _currentTier != 'featured') {
      await _joinWaitlist();
      return;
    }

    setState(() => _processing = true);

    // Stage 20: real Paynow checkout when configured
    final outcome = await PaynowCheckout.run(
      context,
      purpose: 'subscription',
      tier: _selectedTier,
      months: _pricing[_selectedTier]![_selectedPlan]['months'] as int,
    );
    if (outcome != PaynowOutcome.unconfigured) {
      if (mounted) setState(() => _processing = false);
      if (outcome == PaynowOutcome.paid) {
        // Webhook already wrote the subscription row
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Subscription activated — payment received!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
          );
        }
      } else if (mounted &&
          (outcome == PaynowOutcome.failed ||
              outcome == PaynowOutcome.timeout)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(outcome == PaynowOutcome.failed
                ? 'Payment was not completed. Please try again.'
                : 'Payment still pending — refresh this page in a few minutes.'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    try {
      final userId = supabase.auth.currentUser!.id;
      final plan = _pricing[_selectedTier]![_selectedPlan];
      final months = plan['months'] as int;
      final price = plan['price'] as double;

      final startDate = DateTime.now();
      final endDate =
          DateTime(startDate.year, startDate.month + months, startDate.day);

      final payload = {
        'provider_id': userId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'status': 'active',
        'plan': '${months}_month',
        'tier': _selectedTier,
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
        await supabase
            .from('subscriptions')
            .update(payload)
            .eq('provider_id', userId);
      }

      await supabase
          .from('provider_profiles')
          .update({'is_hidden': false}).eq('provider_id', userId);

      // Activating Featured clears any waitlist entry
      if (_selectedTier == 'featured') {
        try {
          await supabase
              .from('featured_waitlist')
              .update({'status': 'activated'}).eq('provider_id', userId);
        } catch (_) {}
      }

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                '${_selectedTier == 'featured' ? 'Featured' : 'Active'} subscription activated for $months month(s)'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
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
                if (_currentTier == 'new' && !_firstBookingUsed)
                  _buildFirstBookingBanner(),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Choose Your Tier',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                      letterSpacing: -0.2),
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildTierCard(
                  tier: 'active',
                  title: 'Active',
                  monthly: 10,
                  icon: Icons.rocket_launch_rounded,
                  color: AppColors.primary,
                  features: const [
                    'Unlimited bookings',
                    'Gallery portfolio',
                    'Run promotions',
                    'Reviews & ratings',
                  ],
                ),
                _buildTierCard(
                  tier: 'featured',
                  title: 'Featured',
                  monthly: 25,
                  icon: Icons.star_rounded,
                  color: AppColors.secondary,
                  features: const [
                    'Everything in Active',
                    'Top 3 placement in search',
                    'Featured badge on profile',
                    'Priority promo tools',
                  ],
                  slotsBanner: true,
                ),
                const SizedBox(height: AppSpacing.lg),
                _buildDurationSelector(),
                const SizedBox(height: AppSpacing.xl),
                _buildInfoBox(),
                const SizedBox(height: AppSpacing.xl),
                _buildSubscribeButton(),
                const SizedBox(height: AppSpacing.xxl),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    final tier = _currentTier;
    final expired = _subscription != null && !_isActive;

    late final List<Color> gradient;
    late final IconData icon;
    late final String title;
    late final String subtitle;

    if (tier == 'featured') {
      gradient = const [Color(0xFFF9A825), Color(0xFFF57F17)];
      icon = Icons.star_rounded;
      title = 'Featured Provider';
      subtitle = '$_daysRemaining days remaining · top of search in your area';
    } else if (tier == 'active') {
      gradient = const [Color(0xFFC2185B), Color(0xFF880E4F)];
      icon = Icons.verified_rounded;
      title = 'Active Subscription';
      subtitle = '$_daysRemaining days remaining · unlimited bookings';
    } else if (expired) {
      gradient = const [Color(0xFFDC2626), Color(0xFFEF4444)];
      icon = Icons.warning_rounded;
      title = 'Subscription Expired';
      subtitle = 'Renew to keep accepting bookings';
    } else {
      gradient = const [Color(0xFF6B7280), Color(0xFF4B5563)];
      icon = Icons.spa_rounded;
      title = 'New Provider — Free';
      subtitle = _firstBookingUsed
          ? 'Free booking used. Subscribe to keep accepting bookings.'
          : 'Your first booking is free — no subscription needed';
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

  Widget _buildFirstBookingBanner() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: AppColors.success.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.success.withValues(alpha: 0.25)),
      ),
      child: const Row(
        children: [
          Icon(Icons.card_giftcard_rounded, color: AppColors.success, size: 22),
          SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'Your first booking is on us! Accept and complete your first booking free, then subscribe to keep going.',
              style: TextStyle(fontSize: 12.5, color: AppColors.textPrimary, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required String tier,
    required String title,
    required int monthly,
    required IconData icon,
    required Color color,
    required List<String> features,
    bool slotsBanner = false,
  }) {
    final isSelected = _selectedTier == tier;
    final slotsLeft = (maxFeaturedPerArea - _featuredInArea).clamp(0, maxFeaturedPerArea);

    return GestureDetector(
      onTap: () => setState(() {
        _selectedTier = tier;
        _selectedPlan = 0;
      }),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: AppSpacing.md),
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.05) : Colors.white,
          border: Border.all(
            color: isSelected ? color : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: AppRadius.lgAll,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                          color: AppColors.textPrimary)),
                ),
                Text('\$$monthly',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 22, color: color)),
                const Text('/mo',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ...features.map((f) => Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Row(
                    children: [
                      Icon(Icons.check_rounded, size: 15, color: color),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(f,
                            style: const TextStyle(
                                fontSize: 13, color: AppColors.textPrimary)),
                      ),
                    ],
                  ),
                )),
            if (slotsBanner) ...[
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(
                  color: (_featuredSlotsFull ? AppColors.warning : AppColors.success)
                      .withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(
                  children: [
                    Icon(
                      _featuredSlotsFull
                          ? Icons.hourglass_top_rounded
                          : Icons.location_on_outlined,
                      size: 15,
                      color: _featuredSlotsFull
                          ? AppColors.warning
                          : AppColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _waitlistEntry != null
                            ? "You're on the waitlist for your area"
                            : _featuredSlotsFull
                                ? 'All $maxFeaturedPerArea Featured slots taken in your area — join the waitlist'
                                : '$slotsLeft of $maxFeaturedPerArea Featured slots open in your area',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _featuredSlotsFull
                              ? AppColors.warning
                              : AppColors.success,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDurationSelector() {
    final plans = _pricing[_selectedTier]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Billing Period',
            style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: plans.asMap().entries.map((entry) {
            final i = entry.key;
            final plan = entry.value;
            final selected = _selectedPlan == i;
            final months = plan['months'] as int;
            final price = plan['price'] as double;
            final perMonth = (price / months).toStringAsFixed(2);

            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _selectedPlan = i),
                child: Container(
                  margin: EdgeInsets.only(right: i < plans.length - 1 ? AppSpacing.sm : 0),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.primary.withValues(alpha: 0.06)
                        : Colors.white,
                    border: Border.all(
                      color: selected ? AppColors.primary : Colors.grey.shade200,
                      width: selected ? 2 : 1,
                    ),
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Column(
                    children: [
                      Text(plan['label'] as String,
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textPrimary)),
                      const SizedBox(height: 2),
                      Text('\$${price.toStringAsFixed(0)}',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: selected
                                  ? AppColors.primary
                                  : AppColors.textPrimary)),
                      Text('\$$perMonth/mo',
                          style: const TextStyle(
                              fontSize: 10.5, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
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
              'Payments via EcoCash & card (Paynow) are coming soon. Subscriptions are currently activated instantly.',
              style: TextStyle(fontSize: 12, color: AppColors.info),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscribeButton() {
    final waitlistMode = _selectedTier == 'featured' &&
        _featuredSlotsFull &&
        _currentTier != 'featured';
    final alreadyWaitlisted = waitlistMode && _waitlistEntry != null;
    final price =
        (_pricing[_selectedTier]![_selectedPlan]['price'] as double)
            .toStringAsFixed(2);

    final label = alreadyWaitlisted
        ? 'On Waitlist — We\'ll Notify You'
        : waitlistMode
            ? 'Join Featured Waitlist'
            : _isActive
                ? 'Renew / Change Tier — \$$price'
                : 'Subscribe — \$$price';

    return Container(
      decoration: BoxDecoration(
        gradient: alreadyWaitlisted ? null : AppColors.primaryGradient,
        color: alreadyWaitlisted ? Colors.grey.shade300 : null,
        borderRadius: AppRadius.mdAll,
      ),
      child: FilledButton.icon(
        onPressed:
            (_processing || alreadyWaitlisted) ? null : _subscribe,
        icon: _processing
            ? const SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(waitlistMode
                ? Icons.hourglass_top_rounded
                : Icons.diamond_outlined),
        label: Text(
          _processing ? 'Processing...' : label,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
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
