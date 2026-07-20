import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _verification;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _subscription;
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser!.id;

    final profile = await supabase
        .from('profiles').select().eq('id', userId).single();

    final adminRows = await supabase
        .from('admins').select().eq('user_id', userId);
    final isAdmin = (adminRows as List).isNotEmpty;

    Map<String, dynamic>? verification;
    try {
      verification = await supabase
          .from('verifications').select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1).single();
    } catch (_) {}

    Map<String, dynamic>? providerProfile;
    Map<String, dynamic>? subscription;

    if (profile['user_type'] == 'provider') {
      try {
        providerProfile = await supabase
            .from('provider_profiles').select()
            .eq('provider_id', userId).single();
      } catch (_) {}

      // Load subscription for providers
      try {
        final sub = await supabase
            .from('subscriptions')
            .select()
            .eq('provider_id', userId)
            .maybeSingle();
        subscription = sub;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _verification = verification;
        _providerProfile = providerProfile;
        _subscription = subscription;
        _isAdmin = isAdmin;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name       = _profile?['full_name'] ?? 'User';
    final userType   = _profile?['user_type'] ?? 'client';
    final isProvider = userType == 'provider';
    final isVerified = _profile?['is_verified'] == true;
    final vStatus    = _verification?['status'];

    // Check if subscription is active
    final bool hasActiveSubscription = _subscription != null &&
        _subscription!['status'] == 'active';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beauty Home Services'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin Panel',
              onPressed: () => context.go('/admin/verify'),
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome hero card
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: AppRadius.lgAll,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.25),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5),
                        width: 2,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Welcome back,',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          name,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(children: [
                          _Badge(
                            label: isProvider ? 'Provider' : 'Client',
                            color: Colors.white.withValues(alpha: 0.2),
                            textColor: Colors.white,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _Badge(
                            label: isVerified ? 'Verified' : 'Unverified',
                            color: isVerified
                                ? AppColors.success.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.2),
                            textColor: Colors.white,
                          ),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: AppSpacing.xl),

            // Verification banner
            if (!isVerified) ...[
              _VerificationBanner(
                status: vStatus,
                onTap: () {
                  if (vStatus == null || vStatus == 'rejected') {
                    context.go('/verify');
                  } else {
                    context.go('/verify/pending');
                  }
                },
              ),
              const SizedBox(height: AppSpacing.xl),
            ],

            // Provider dashboard
            if (isProvider && isVerified) ...[
              Text(
                'Provider Dashboard',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),

              // Availability status
              if (_providerProfile != null)
                _AvailabilityCard(
                  status: _providerProfile!['availability_status'],
                  onChanged: (newStatus) async {
                    await supabase
                        .from('provider_profiles')
                        .update({'availability_status': newStatus})
                        .eq('provider_id', supabase.auth.currentUser!.id);
                    setState(() =>
                        _providerProfile!['availability_status'] = newStatus);
                  },
                ),

              const SizedBox(height: AppSpacing.md),

              // Subscription warning banner
              if (!hasActiveSubscription)
                GestureDetector(
                  onTap: () => context.go('/provider/subscription'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: AppSpacing.md),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.08),
                      borderRadius: AppRadius.lgAll,
                      border: Border.all(
                        color: AppColors.error.withValues(alpha: 0.25),
                      ),
                    ),
                    child: Row(children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppColors.error.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.workspace_premium_rounded,
                          color: AppColors.error,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          'No active subscription — your profile is hidden from clients.',
                          style: TextStyle(
                            color: AppColors.error,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(Icons.chevron_right, color: AppColors.error),
                    ]),
                  ),
                ),

              // Dashboard tiles
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: AppSpacing.md,
                mainAxisSpacing: AppSpacing.md,
                childAspectRatio: 1.4,
                children: [
                  _DashTile(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    color: AppColors.info,
                    onTap: () => context.go('/provider/profile/edit'),
                  ),
                  _DashTile(
                    icon: Icons.content_cut_rounded,
                    label: 'My Services',
                    color: AppColors.secondary,
                    onTap: () => context.go('/provider/services'),
                  ),
                  _DashTile(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: AppColors.accent,
                    onTap: () => context.go('/provider/gallery'),
                  ),
                  _DashTile(
                    icon: Icons.public_outlined,
                    label: 'My Public Profile',
                    color: AppColors.available,
                    onTap: () => context.go('/provider/${supabase.auth.currentUser!.id}'),
                  ),
                  _DashTile(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Subscription',
                    color: AppColors.success,
                    onTap: () => context.go('/provider/subscription'),
                  ),
                  _DashTile(
                    icon: Icons.calendar_month_rounded,
                    label: 'Bookings',
                    color: AppColors.warning,
                    onTap: () => context.go('/provider/bookings'),
                  ),
                  _DashTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'My Earnings',
                    color: AppColors.success,
                    onTap: () => context.go('/earnings'),
                  ),
                ],
              ),
            ],

            // Provider not yet set up
            if (isProvider && isVerified && _providerProfile == null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.info.withValues(alpha: 0.08),
                      AppColors.info.withValues(alpha: 0.03),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.2),
                  ),
                ),
                padding: AppSpacing.cardPadding,
                child: Column(
                  children: [
                    const Text(
                      'Complete your provider profile to appear in search results.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    FilledButton(
                      onPressed: () {
                        context.go('/provider/profile/edit');
                      },
                      child: const Text('Set Up Profile'),
                    ),
                  ],
                ),
              ),
            ],

            // Client home
            if (!isProvider && isVerified) ...[
              Text(
                'Find a Stylist',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: AppSpacing.md),
              _DashTile(
                icon: Icons.search_rounded,
                label: 'Browse Stylists',
                color: AppColors.info,
                onTap: () => context.go('/browse'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DashTile(
                icon: Icons.calendar_today_outlined,
                label: 'My Bookings',
                color: AppColors.primary,
                onTap: () => context.go('/client/bookings'),
              ),
              const SizedBox(height: AppSpacing.sm),
              _DashTile(
                icon: Icons.favorite_rounded,
                label: 'Favourite Stylists',
                color: AppColors.error,
                onTap: () => context.go('/favorites'),
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(
                    color: AppColors.info.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.info_outline,
                        size: 15,
                        color: AppColors.info,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    const Expanded(
                      child: Text(
                        'Browse available stylists and tap "Book Now" to schedule an appointment.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.info,
                          fontWeight: FontWeight.w500,
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
}

class _AvailabilityCard extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  const _AvailabilityCard({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    IconData statusIcon;
    switch (status) {
      case 'available':
        color = AppColors.available;
        label = 'Available';
        statusIcon = Icons.check_circle_rounded;
        break;
      case 'busy':
        color = AppColors.busy;
        label = 'Busy';
        statusIcon = Icons.pause_circle_filled_rounded;
        break;
      default:
        color = AppColors.offline;
        label = 'Offline';
        statusIcon = Icons.cancel_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(statusIcon, color: color, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Status',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textTertiary,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: color,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: onChanged,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'available',
                child: Row(children: [
                  Icon(Icons.check_circle_rounded, color: AppColors.available, size: 18),
                  const SizedBox(width: 8),
                  const Text('Available'),
                ]),
              ),
              PopupMenuItem(
                value: 'busy',
                child: Row(children: [
                  Icon(Icons.pause_circle_filled_rounded, color: AppColors.busy, size: 18),
                  const SizedBox(width: 8),
                  const Text('Busy'),
                ]),
              ),
              PopupMenuItem(
                value: 'offline',
                child: Row(children: [
                  Icon(Icons.cancel_rounded, color: AppColors.offline, size: 18),
                  const SizedBox(width: 8),
                  const Text('Offline'),
                ]),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: AppRadius.smAll,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Change',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.keyboard_arrow_down_rounded, color: color, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DashTile({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: AppSpacing.cardPadding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.04),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: color.withValues(alpha: 0.15)),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final String? status;
  final VoidCallback onTap;
  const _VerificationBanner({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color bannerColor;
    String message;
    IconData icon;
    switch (status) {
      case 'pending':
        bannerColor = AppColors.warning;
        message = 'Your verification is under review. Tap to see status.';
        icon = Icons.hourglass_top_rounded;
        break;
      case 'rejected':
        bannerColor = AppColors.error;
        message = 'Verification rejected. Tap to re-submit your documents.';
        icon = Icons.cancel_outlined;
        break;
      default:
        bannerColor = AppColors.info;
        message = 'Verify your identity to unlock all features. Tap to start.';
        icon = Icons.verified_user_outlined;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: AppSpacing.cardPadding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              bannerColor.withValues(alpha: 0.1),
              bannerColor.withValues(alpha: 0.04),
            ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: bannerColor.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: bannerColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: bannerColor, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Icon(Icons.chevron_right, color: bannerColor),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label; final Color color; final Color textColor;
  const _Badge({required this.label, required this.color, required this.textColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: AppRadius.smAll,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
