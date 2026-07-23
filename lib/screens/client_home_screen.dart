import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _verification;
  bool _isAdmin = false;
  bool _loading = true;
  int _unreadNotifications = 0;
  late AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _loadData();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.maybeInit(context);
    });
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    Map<String, dynamic> profile;
    try {
      profile = await supabase
          .from('profiles').select().eq('id', userId).single();
    } catch (_) {
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
      return;
    }

    final adminRows = await supabase
        .from('admins').select().eq('user_id', userId);
    final isAdmin = (adminRows as List).isNotEmpty;

    Map<String, dynamic>? verification;
    try {
      verification = await supabase
          .from('verifications').select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1).maybeSingle();
    } catch (_) {}

    int unreadNotifs = 0;
    try {
      unreadNotifs = await NotificationService.unreadCount(userId);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _profile = profile;
        _verification = verification;
        _isAdmin = isAdmin;
        _unreadNotifications = unreadNotifs;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 40, height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
              const SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final name = _profile?['full_name'] ?? 'User';
    final isVerified = _profile?['is_verified'] == true;
    final vStatus = _verification?['status'];

    return Scaffold(
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 160,
            pinned: true,
            backgroundColor: AppColors.primary,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: const BrandTitle(),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
                  tooltip: 'Admin Panel',
                  onPressed: () => context.push('/admin/dashboard'),
                ),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (_unreadNotifications > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
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
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: GestureDetector(
                      onTap: () => context.push('/account/settings'),
                      child: Row(
                        children: [
                          Container(
                            width: 50, height: 50,
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
                                Text('Welcome back,', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                                Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                                const SizedBox(height: 5),
                                Row(children: [
                                  _Badge(label: 'Client'),
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
          ),

          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isVerified) ...[
                          _VerificationBanner(
                            status: vStatus,
                            onTap: () {
                              if (vStatus == null || vStatus == 'rejected') {
                                context.push('/verify');
                              } else {
                                context.push('/verify/pending');
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        if (isVerified && _profile?['is_activated'] == false) ...[
                          _ActivationBanner(onTap: () => context.push('/activation')),
                          const SizedBox(height: 14),
                        ],

                        if (!isVerified) ...[
                          _GettingStartedCard(vStatus: vStatus),
                          const SizedBox(height: 18),
                        ],

                        const Text('Quick Actions', style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                        )),
                        const SizedBox(height: 10),
                        _buildClientTiles(isVerified),

                        if (!isVerified) ...[
                          const SizedBox(height: 18),
                          _WhyVerifyCard(),
                        ],

                        const SizedBox(height: 20),
                        const Text('Account', style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                        )),
                        const SizedBox(height: 10),
                        _AccountTile(
                          icon: Icons.settings_outlined,
                          label: 'Account Settings',
                          subtitle: 'Manage, deactivate, or delete your account',
                          onTap: () => context.push('/account/settings'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientTiles(bool isVerified) {
    final tiles = [
      _TileData(Icons.search_rounded, 'Browse Stylists', AppColors.primary, '/browse', true),
      _TileData(Icons.auto_awesome_rounded, 'For You', AppColors.secondary, '/recommended', isVerified),
      _TileData(Icons.calendar_today_outlined, 'My Bookings', AppColors.info, '/client/bookings', isVerified),
      _TileData(Icons.favorite_rounded, 'Favourites', AppColors.error, '/favorites', isVerified),
    ];
    return _TileGrid(tiles: tiles);
  }
}

class _TileData {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  final bool enabled;
  const _TileData(this.icon, this.label, this.color, this.route, this.enabled);
}

class _TileGrid extends StatelessWidget {
  final List<_TileData> tiles;
  const _TileGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 450 ? 4 : 2;
        final spacing = 10.0;
        final tileWidth = (constraints.maxWidth - spacing * (crossCount - 1)) / crossCount;
        return Wrap(
          spacing: spacing, runSpacing: 12,
          children: tiles.map((t) => SizedBox(
            width: tileWidth,
            child: _DashTile(
              icon: t.icon,
              label: t.label,
              color: t.color,
              enabled: t.enabled,
              onTap: () {
                if (t.enabled) {
                  const shellRoutes = {'/home', '/browse', '/client/bookings', '/favorites'};
                  if (shellRoutes.contains(t.route)) {
                    context.go(t.route);
                  } else {
                    context.push(t.route);
                  }
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Verify your identity to unlock this feature.'),
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                      backgroundColor: AppColors.primary,
                    ),
                  );
                }
              },
            ),
          )).toList(),
        );
      },
    );
  }
}

class _DashTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool enabled;
  final VoidCallback onTap;
  const _DashTile({required this.icon, required this.label, required this.color, required this.onTap, this.enabled = true});
  @override
  State<_DashTile> createState() => _DashTileState();
}

class _DashTileState extends State<_DashTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final effectiveColor = widget.enabled ? widget.color : Colors.grey.shade400;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
          decoration: BoxDecoration(
            color: _hovering && widget.enabled ? effectiveColor.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _hovering && widget.enabled ? effectiveColor.withValues(alpha: 0.3) : Colors.grey.shade200),
            boxShadow: _hovering && widget.enabled
                ? [BoxShadow(color: effectiveColor.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [effectiveColor.withValues(alpha: 0.15), effectiveColor.withValues(alpha: 0.06)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Icon(widget.icon, color: effectiveColor, size: 22),
                    if (!widget.enabled)
                      Positioned(
                        right: 2, bottom: 2,
                        child: Container(
                          width: 14, height: 14,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                          ),
                          child: Icon(Icons.lock, size: 8, color: Colors.grey.shade500),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(widget.label, maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600,
                    color: _hovering && widget.enabled ? effectiveColor : AppColors.textPrimary,
                    height: 1.2,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _GettingStartedCard extends StatelessWidget {
  final String? vStatus;
  const _GettingStartedCard({this.vStatus});

  @override
  Widget build(BuildContext context) {
    final steps = <_StepItem>[
      _StepItem('Create your account', true),
      _StepItem('Verify your identity', vStatus == 'approved'),
      _StepItem('Activate & start booking', false),
    ];

    final completedCount = steps.where((s) => s.done).length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Getting Started', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('$completedCount of ${steps.length} steps complete', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: completedCount / steps.length,
              minHeight: 6,
              backgroundColor: Colors.grey.shade100,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
          const SizedBox(height: 14),
          ...steps.map((s) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Container(
                  width: 22, height: 22,
                  decoration: BoxDecoration(
                    color: s.done ? AppColors.success : Colors.grey.shade200,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    s.done ? Icons.check_rounded : Icons.circle_outlined,
                    size: 14,
                    color: s.done ? Colors.white : Colors.grey.shade400,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  s.label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: s.done ? AppColors.textTertiary : AppColors.textPrimary,
                    decoration: s.done ? TextDecoration.lineThrough : null,
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _StepItem {
  final String label;
  final bool done;
  const _StepItem(this.label, this.done);
}

class _WhyVerifyCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      _InfoItem(Icons.search_rounded, 'Discover', 'Find top-rated stylists near you'),
      _InfoItem(Icons.calendar_month_rounded, 'Book', 'Schedule appointments in seconds'),
      _InfoItem(Icons.home_rounded, 'Relax', 'Get beauty services at your doorstep'),
    ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.04),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Why verify?', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const SizedBox(height: 4),
          Text(
            'Verification keeps our community safe and unlocks the full BeauTap experience.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          ...items.map((item) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(item.icon, color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      Text(item.subtitle, style: TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
                    ],
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }
}

class _InfoItem {
  final IconData icon;
  final String title;
  final String subtitle;
  const _InfoItem(this.icon, this.title, this.subtitle);
}

class _ActivationBanner extends StatelessWidget {
  final VoidCallback onTap;
  const _ActivationBanner({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(children: [
          const Icon(Icons.lock_open_rounded, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Activate your account for \$1 — one time — to unlock unlimited bookings.',
              style: TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          const Icon(Icons.chevron_right, color: Colors.white, size: 20),
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

class _AccountTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _AccountTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: AppColors.textSecondary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: AppColors.textSecondary, size: 20),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
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
