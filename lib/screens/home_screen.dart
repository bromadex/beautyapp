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
    final bool hasActiveSubscription = _subscription != null &&
        _subscription!['status'] == 'active';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Gradient app bar
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppColors.primary,
            surfaceTintColor: Colors.transparent,
            title: const Text(
              'Beauty Home Services',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
            ),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
                  tooltip: 'Admin Panel',
                  onPressed: () => context.go('/admin/verify'),
                ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                onPressed: _signOut,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
                    child: Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white38, width: 2),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Welcome back,', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                              Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                              const SizedBox(height: 6),
                              Row(children: [
                                _Badge(label: isProvider ? 'Provider' : 'Client'),
                                const SizedBox(width: 6),
                                _Badge(label: isVerified ? 'Verified' : 'Unverified', isPositive: isVerified),
                              ]),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // Body
          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
                        const SizedBox(height: 16),
                      ],

                      // Provider dashboard
                      if (isProvider && isVerified) ...[
                        // Availability
                        if (_providerProfile != null) ...[
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
                          const SizedBox(height: 12),
                        ],

                        // Subscription warning
                        if (!hasActiveSubscription) ...[
                          _WarningBanner(
                            text: 'No active subscription — your profile is hidden.',
                            onTap: () => context.go('/provider/subscription'),
                          ),
                          const SizedBox(height: 12),
                        ],

                        // Quick actions header
                        Padding(
                          padding: const EdgeInsets.only(left: 4, top: 4, bottom: 10),
                          child: Text('Quick Actions',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.5),
                          ),
                        ),

                        // Dashboard tiles - 2 column grid
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _DashTile(icon: Icons.person_outline, label: 'Edit Profile', color: AppColors.info, onTap: () => context.go('/provider/profile/edit')),
                            _DashTile(icon: Icons.content_cut_rounded, label: 'My Services', color: AppColors.secondary, onTap: () => context.go('/provider/services')),
                            _DashTile(icon: Icons.photo_library_outlined, label: 'Gallery', color: AppColors.accent, onTap: () => context.go('/provider/gallery')),
                            _DashTile(icon: Icons.calendar_month_rounded, label: 'Bookings', color: AppColors.warning, onTap: () => context.go('/provider/bookings')),
                            _DashTile(icon: Icons.workspace_premium_rounded, label: 'Subscription', color: AppColors.success, onTap: () => context.go('/provider/subscription')),
                            _DashTile(icon: Icons.account_balance_wallet_rounded, label: 'Earnings', color: AppColors.success, onTap: () => context.go('/earnings')),
                            _DashTile(icon: Icons.public_outlined, label: 'Public Profile', color: AppColors.info, onTap: () => context.go('/provider/${supabase.auth.currentUser!.id}')),
                          ],
                        ),
                      ],

                      // Provider not yet set up
                      if (isProvider && isVerified && _providerProfile == null) ...[
                        const SizedBox(height: 8),
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.info.withValues(alpha: 0.06),
                            borderRadius: AppRadius.lgAll,
                            border: Border.all(color: AppColors.info.withValues(alpha: 0.15)),
                          ),
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            children: [
                              Icon(Icons.rocket_launch_rounded, size: 36, color: AppColors.info),
                              const SizedBox(height: 10),
                              const Text('Complete your provider profile to appear in search results.',
                                  textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                              const SizedBox(height: 12),
                              FilledButton(
                                onPressed: () => context.go('/provider/profile/edit'),
                                child: const Text('Set Up Profile'),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Client home
                      if (!isProvider && isVerified) ...[
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text('What would you like to do?',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.5),
                          ),
                        ),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            _DashTile(icon: Icons.search_rounded, label: 'Browse Stylists', color: AppColors.primary, onTap: () => context.go('/browse')),
                            _DashTile(icon: Icons.calendar_today_outlined, label: 'My Bookings', color: AppColors.info, onTap: () => context.go('/client/bookings')),
                            _DashTile(icon: Icons.favorite_rounded, label: 'Favourites', color: AppColors.error, onTap: () => context.go('/favorites')),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
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
  const _DashTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tileWidth = (constraints.maxWidth - 10) / 2;
        return SizedBox(
          width: tileWidth,
          height: 100,
          child: Material(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            child: InkWell(
              onTap: onTap,
              borderRadius: AppRadius.mdAll,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.1),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(icon, color: color, size: 20),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
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
        color = AppColors.available; label = 'Available'; statusIcon = Icons.check_circle_rounded; break;
      case 'busy':
        color = AppColors.busy; label = 'Busy'; statusIcon = Icons.pause_circle_filled_rounded; break;
      default:
        color = AppColors.offline; label = 'Offline'; statusIcon = Icons.cancel_rounded;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(statusIcon, color: color, size: 20),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color, fontSize: 14)),
          const Spacer(),
          PopupMenuButton<String>(
            onSelected: onChanged,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'available', child: Row(children: [Icon(Icons.check_circle_rounded, color: AppColors.available, size: 18), const SizedBox(width: 8), const Text('Available')])),
              PopupMenuItem(value: 'busy', child: Row(children: [Icon(Icons.pause_circle_filled_rounded, color: AppColors.busy, size: 18), const SizedBox(width: 8), const Text('Busy')])),
              PopupMenuItem(value: 'offline', child: Row(children: [Icon(Icons.cancel_rounded, color: AppColors.offline, size: 18), const SizedBox(width: 8), const Text('Offline')])),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: AppRadius.smAll),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Change', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                  const SizedBox(width: 2),
                  Icon(Icons.keyboard_arrow_down_rounded, color: color, size: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _WarningBanner({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w500))),
          Icon(Icons.chevron_right, color: AppColors.error, size: 18),
        ]),
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
        message = 'Verification under review. Tap to check status.';
        icon = Icons.hourglass_top_rounded; break;
      case 'rejected':
        bannerColor = AppColors.error;
        message = 'Verification rejected. Tap to re-submit.';
        icon = Icons.cancel_outlined; break;
      default:
        bannerColor = AppColors.info;
        message = 'Verify your identity to unlock all features.';
        icon = Icons.verified_user_outlined;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.06),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: bannerColor.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: bannerColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: bannerColor, fontWeight: FontWeight.w500))),
          Icon(Icons.chevron_right, color: bannerColor, size: 18),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final bool isPositive;
  const _Badge({required this.label, this.isPositive = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.success.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}
