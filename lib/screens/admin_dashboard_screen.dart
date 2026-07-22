import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

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
  int _pendingVerifications = 0;
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
      final profiles = await supabase.from('profiles').select('user_type');
      final profilesList = List<Map<String, dynamic>>.from(profiles);
      _totalUsers = profilesList.length;
      _totalProviders = profilesList.where((p) => p['user_type'] == 'provider').length;
      _totalClients = profilesList.where((p) => p['user_type'] == 'client').length;

      final bookings = await supabase.from('bookings').select('status, total_price');
      final bookingsList = List<Map<String, dynamic>>.from(bookings);
      _totalBookings = bookingsList.length;
      _completedBookings = bookingsList.where((b) => b['status'] == 'completed').length;

      _totalRevenue = 0;
      for (final b in bookingsList) {
        if (b['status'] == 'completed' && b['total_price'] != null) {
          _totalRevenue += (b['total_price'] as num).toDouble();
        }
      }
      // Platform revenue = provider subscriptions only (no commission)
      _subscriptionRevenue = 0;
      try {
        final subs = await supabase.from('subscriptions').select('amount_paid');
        for (final s in List<Map<String, dynamic>>.from(subs)) {
          _subscriptionRevenue += (s['amount_paid'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      final pendingV = await supabase
          .from('verifications')
          .select('id')
          .eq('status', 'pending');
      _pendingVerifications = (pendingV as List).length;

      final recent = await supabase
          .from('bookings')
          .select('*, services(service_name), profiles!bookings_client_id_fkey(full_name)')
          .order('created_at', ascending: false)
          .limit(5);
      _recentBookings = List<Map<String, dynamic>>.from(recent);

      final providers = await supabase
          .from('profiles')
          .select('id, full_name')
          .eq('user_type', 'provider');
      final providersList = List<Map<String, dynamic>>.from(providers);

      List<Map<String, dynamic>> topProvs = [];
      for (final p in providersList) {
        final reviews = await supabase
            .from('reviews')
            .select('rating')
            .eq('provider_id', p['id']);
        final reviewsList = List<Map<String, dynamic>>.from(reviews);
        if (reviewsList.isEmpty) continue;
        final avgRating = reviewsList.fold<double>(0, (sum, r) => sum + (r['rating'] as num).toDouble()) / reviewsList.length;
        final bookingCount = bookingsList.where((b) => b['provider_id'] == p['id'] && b['status'] == 'completed').length;
        topProvs.add({
          'name': p['full_name'] ?? 'Unknown',
          'rating': avgRating,
          'reviews': reviewsList.length,
          'bookings': bookingCount,
        });
      }
      topProvs.sort((a, b) => (b['rating'] as double).compareTo(a['rating'] as double));
      _topProviders = topProvs.take(5).toList();

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

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadStats),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadStats,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.md,
      mainAxisSpacing: AppSpacing.md,
      childAspectRatio: 1.5,
      children: [
        _StatCard(
          icon: Icons.people_rounded,
          label: 'Total Users',
          value: '$_totalUsers',
          subtitle: '$_totalProviders providers, $_totalClients clients',
          color: AppColors.info,
          onTap: () => context.push('/admin/users'),
        ),
        _StatCard(
          icon: Icons.calendar_today_rounded,
          label: 'Bookings',
          value: '$_totalBookings',
          subtitle: '$_completedBookings completed',
          color: AppColors.secondary,
          onTap: () => context.push('/admin/bookings'),
        ),
        _StatCard(
          icon: Icons.attach_money_rounded,
          label: 'Bookings Volume',
          value: '\$${_totalRevenue.toStringAsFixed(0)}',
          subtitle: '\$${_subscriptionRevenue.toStringAsFixed(0)} subscription revenue',
          color: AppColors.success,
          onTap: () => context.push('/admin/analytics'),
        ),
        _StatCard(
          icon: Icons.verified_user_rounded,
          label: 'Verifications',
          value: '$_pendingVerifications',
          subtitle: 'pending review',
          color: _pendingVerifications > 0 ? AppColors.warning : AppColors.success,
          onTap: () => context.push('/admin/verify'),
        ),
      ],
    );
  }

  Widget _buildActionTiles() {
    final actions = [
      _ActionItem(Icons.people_outline_rounded, 'Users', AppColors.info, () => context.push('/admin/users')),
      _ActionItem(Icons.calendar_month_rounded, 'Bookings', AppColors.secondary, () => context.push('/admin/bookings')),
      _ActionItem(Icons.verified_rounded, 'Verifications', AppColors.warning, () => context.push('/admin/verify')),
      _ActionItem(Icons.bar_chart_rounded, 'Analytics', AppColors.success, () => context.push('/admin/analytics')),
    ];

    return GridView.count(
      crossAxisCount: 4,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: AppSpacing.sm,
      mainAxisSpacing: AppSpacing.sm,
      childAspectRatio: 0.85,
      children: actions.map((a) => _buildActionTile(a)).toList(),
    );
  }

  Widget _buildActionTile(_ActionItem item) {
    return InkWell(
      onTap: item.onTap,
      borderRadius: AppRadius.lgAll,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: item.color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(item.icon, color: item.color, size: 22),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              item.label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopProviders() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: List.generate(_topProviders.length, (i) {
          final p = _topProviders[i];
          return Column(
            children: [
              if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: i < 3 ? AppColors.warning.withValues(alpha: 0.1) : Colors.grey.shade100,
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
                        const Icon(Icons.star_rounded, color: AppColors.warning, size: 16),
                        const SizedBox(width: 2),
                        Text(
                          (p['rating'] as double).toStringAsFixed(1),
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '${p['reviews']} reviews',
                          style: const TextStyle(fontSize: 11, color: AppColors.textTertiary),
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
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: const Center(
          child: Text('No bookings yet', style: TextStyle(color: AppColors.textTertiary)),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
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
              if (i > 0) Divider(height: 1, color: Colors.grey.shade200),
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
                          Icons.calendar_today_rounded,
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
                              style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
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
                              'R${(price as num).toStringAsFixed(0)}',
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
          color: Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(color: Colors.grey.shade200),
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
                Icon(Icons.arrow_forward_ios_rounded, size: 12, color: AppColors.textTertiary),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              value,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
            ),
            Text(
              subtitle,
              style: const TextStyle(fontSize: 10, color: AppColors.textTertiary),
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
  const _ActionItem(this.icon, this.label, this.color, this.onTap);
}
