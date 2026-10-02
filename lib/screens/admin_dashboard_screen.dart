import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  bool _loading = true;
  bool _isAdmin = false;

  int _totalUsers = 0;
  int _totalProviders = 0;
  int _totalClients = 0;
  int _totalBookings = 0;
  int _completedBookings = 0;
  Map<String, dynamic> _stats = {};
  double _totalRevenue = 0;
  double _subscriptionRevenue = 0;
  List<Map<String, dynamic>> _recentBookings = [];
  List<Map<String, dynamic>> _topProviders = [];

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoad();
  }

  Future<void> _checkAdminAndLoad() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    final adminRows = await supabase.from('admins').select().eq('user_id', userId);
    if ((adminRows as List).isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Access denied')),
        );
        context.go('/home');
      }
      return;
    }

    setState(() => _isAdmin = true);
    await _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _loading = true);
    try {
      final res = await Future.wait<dynamic>([
        supabase.rpc('admin_stats'),
        supabase
            .from('bookings')
            .select('*, services(service_name), profiles!bookings_client_id_fkey(full_name)')
            .eq('source', 'app')
            .order('created_at', ascending: false)
            .limit(5),
      ]);
      _stats = Map<String, dynamic>.from(res[0] as Map);
      final u = _m('users'), b = _m('bookings'), inc = _m('income');
      _totalUsers = _n(u['total']);
      _totalProviders = _n(u['providers']);
      _totalClients = _n(u['clients']);
      _totalBookings = _n(b['total']);
      _completedBookings = _n(b['completed']);
      _totalRevenue = (b['completed_value'] as num?)?.toDouble() ?? 0;
      _subscriptionRevenue = (inc['total'] as num?)?.toDouble() ?? 0;
      _recentBookings = List<Map<String, dynamic>>.from(res[1] as List);
      _topProviders = [
        for (final p in (_stats['top_providers'] as List? ?? []))
          {
            'name': p['name'] ?? 'Unknown',
            'rating': (p['rating'] as num?)?.toDouble() ?? 0,
            'reviews': _n(p['reviews']),
            'bookings': _n(p['bookings']),
          }
      ];
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stats: $e')),
        );
      }
    }
  }

  Widget _urgentBanner() {
    final n = _n(_m('todo')['sexual_conduct']);
    return InkWell(
      onTap: () => context.push('/admin/disputes'),
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.errorSoft,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.error),
        ),
        child: Row(children: [
          Icon(TablerIcons.alert_triangle, color: AppColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$n sexual-conduct report${n == 1 ? '' : 's'} waiting. Please look at ${n == 1 ? 'it' : 'them'} first.',
              style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700),
            ),
          ),
          Icon(TablerIcons.chevron_right, color: AppColors.error),
        ]),
      ),
    );
  }

  Map<String, dynamic> _m(String k) => Map<String, dynamic>.from(_stats[k] as Map? ?? {});
  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;
  static String _money(num v) => '\$${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        body: const LoadingPlaceholder(kind: PlaceholderKind.detail),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(icon: const Icon(TablerIcons.refresh), onPressed: _loadStats),
        ],
      ),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_n(_m('todo')['sexual_conduct']) > 0) ...[
                      _urgentBanner(),
                      const SizedBox(height: AppSpacing.md),
                    ],
                    // Quick Stats Grid
                    _buildStatsGrid(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Admin Actions
                    Text('Manage', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _buildActionTiles(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Top Providers
                    if (_topProviders.isNotEmpty) ...[
                      Text('Top Providers', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      _buildTopProviders(),
                      const SizedBox(height: AppSpacing.xxl),
                    ],

                    // Recent Bookings
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Recent Bookings', style: Theme.of(context).textTheme.titleMedium),
                        TextButton(
                          onPressed: () => context.push('/admin/bookings'),
                          child: const Text('View All'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _buildRecentBookings(),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatsGrid() {
    final u = _m('users'), inc = _m('income');
    final noLocation = _n(u['pros_no_location']);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          icon: TablerIcons.users,
          label: 'Users',
          value: '$_totalUsers',
          subtitle: '$_totalProviders pros · $_totalClients clients',
          color: AppColors.info,
          onTap: () => context.push('/admin/users'),
        ),
        _StatCard(
          icon: TablerIcons.scissors,
          label: 'Pros clients can find',
          value: '${_n(u['pros_findable'])}',
          subtitle: noLocation > 0 ? '$noLocation without a location' : 'of $_totalProviders pros',
          color: noLocation > 0 ? AppColors.warning : AppColors.success,
          onTap: () => context.push('/admin/users'),
        ),
        _StatCard(
          icon: TablerIcons.calendar,
          label: 'Bookings',
          value: '$_totalBookings',
          subtitle: '$_completedBookings done · ${_money(_totalRevenue)} paid to pros',
          color: AppColors.secondary,
          onTap: () => context.push('/admin/bookings'),
        ),
        _StatCard(
          icon: TablerIcons.currency_dollar,
          label: 'BeauTap income',
          value: _money(_subscriptionRevenue),
          subtitle: '${_money((inc['this_month'] as num?) ?? 0)} this month',
          color: AppColors.success,
          onTap: () => context.push('/admin/analytics'),
        ),
      ],
    );
  }

  Widget _buildActionTiles() {
    final t = _m('todo');
    final actions = [
      _ActionItem(TablerIcons.users, 'Users', AppColors.info, () => context.push('/admin/users')),
      _ActionItem(TablerIcons.device_mobile_dollar, 'EcoCash fees', AppColors.success, () => context.push('/admin/fees'), _n(t['fees'])),
      _ActionItem(TablerIcons.calendar_month, 'Bookings', AppColors.secondary, () => context.push('/admin/bookings')),
      _ActionItem(TablerIcons.rosette_discount_check, 'Verifications', AppColors.warning, () => context.push('/admin/verify'), _n(t['verifications'])),
      _ActionItem(TablerIcons.chart_bar, 'Analytics', AppColors.success, () => context.push('/admin/analytics')),
      _ActionItem(TablerIcons.flag, 'Disputes', AppColors.error, () => context.push('/admin/disputes'), _n(t['disputes'])),
      _ActionItem(TablerIcons.building_store, 'Businesses', AppColors.primary, () => context.push('/admin/business'), _n(t['business'])),
      _ActionItem(TablerIcons.message_star, 'Reported reviews', AppColors.warning, () => context.push('/admin/moderation'), _n(t['reported_reviews'])),
      _ActionItem(TablerIcons.map, 'Area demand', AppColors.info, () => context.push('/admin/moderation?tab=demand')),
      _ActionItem(TablerIcons.shield_check, 'Flagged services', AppColors.error, () => context.push('/admin/moderation?tab=flagged'), _n(t['flagged_services'])),
      _ActionItem(TablerIcons.bug, 'App errors', AppColors.error, () => context.push('/admin/errors'), _n(t['errors'])),
    ];

    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 1.1,
      children: actions.map((a) => _buildActionTile(a)).toList(),
    );
  }

  Widget _buildActionTile(_ActionItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: AppRadius.lgAll,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: item.count > 0,
              label: Text('${item.count}'),
              backgroundColor: AppColors.error,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.color, size: 22),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProviders() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(_topProviders.length, (i) {
          final p = _topProviders[i];
          return Column(
            children: [
              if (i > 0) Divider(height: 1, color: AppColors.border),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: i < 3 ? AppColors.warning.withValues(alpha: 0.1) : AppColors.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: i < 3 ? AppColors.warning : AppColors.textTertiary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Text(
                        p['name'],
                        style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(TablerIcons.star_filled, color: AppColors.warning, size: 16),
                        const SizedBox(width: 2),
                        Text(
                          (p['rating'] as double).toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${p['reviews']} reviews',
                          style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildRecentBookings() {
    if (_recentBookings.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Center(
          child: Text('No bookings yet', style: TextStyle(color: AppColors.textTertiary)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: List.generate(_recentBookings.length, (i) {
          final b = _recentBookings[i];
          final clientName = b['profiles']?['full_name'] ?? 'Unknown';
          final serviceName = b['services']?['service_name'] ?? 'Service';
          final status = b['status'] ?? 'pending';
          final price = b['total_price'];

          return Column(
            children: [
              if (i > 0) Divider(height: 1, color: AppColors.border),
              InkWell(
                onTap: () => context.push('/booking/${b['id']}'),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: StatusColors.background(status),
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Icon(
                          TablerIcons.calendar,
                          color: StatusColors.foreground(status),
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              serviceName,
                              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              clientName,
                              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                            decoration: BoxDecoration(
                              color: StatusColors.background(status),
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Text(
                              StatusColors.label(status),
                              style: TextStyle(
                                color: StatusColors.foreground(status),
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          if (price != null) ...[
                            const SizedBox(height: 4),
                            Text(
                              '\$${(price as num).toStringAsFixed(0)}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String subtitle;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.subtitle,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const Spacer(),
                Icon(TablerIcons.chevron_right, size: 12, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10, color: AppColors.textTertiary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionItem {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  final int count;
  const _ActionItem(this.icon, this.label, this.color, this.onTap, [this.count = 0]);
}
