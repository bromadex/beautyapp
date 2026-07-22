import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AdminAnalyticsScreen extends StatefulWidget {
  const AdminAnalyticsScreen({super.key});

  @override
  State<AdminAnalyticsScreen> createState() => _AdminAnalyticsScreenState();
}

class _AdminAnalyticsScreenState extends State<AdminAnalyticsScreen> {
  bool _loading = true;

  // Revenue
  double _totalRevenue = 0;
  double _subscriptionRevenue = 0;
  double _thisMonthRevenue = 0;
  double _lastMonthRevenue = 0;

  // Bookings
  int _totalBookings = 0;
  int _thisMonthBookings = 0;
  int _lastMonthBookings = 0;
  Map<String, int> _statusCounts = {};

  // Users
  int _totalUsers = 0;
  int _newUsersThisMonth = 0;
  int _totalProviders = 0;
  int _verifiedProviders = 0;

  // Services
  List<Map<String, dynamic>> _popularServices = [];

  // Monthly breakdown
  List<Map<String, dynamic>> _monthlyRevenue = [];

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoad();
  }

  Future<void> _checkAdminAndLoad() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    final adminRows = await supabase.from('admins').select().eq('user_id', userId);
    if ((adminRows as List).isEmpty) {
      if (mounted) context.go('/home');
      return;
    }
    await _loadAnalytics();
  }

  Future<void> _loadAnalytics() async {
    setState(() => _loading = true);
    try {
      final now = DateTime.now();
      final thisMonthStart = DateTime(now.year, now.month, 1).toIso8601String().substring(0, 10);
      final lastMonthStart = DateTime(now.year, now.month - 1, 1).toIso8601String().substring(0, 10);
      final lastMonthEnd = DateTime(now.year, now.month, 0).toIso8601String().substring(0, 10);

      // Bookings
      final bookings = await supabase.from('bookings').select('status, total_price, created_at, services(service_name)');
      final bookingsList = List<Map<String, dynamic>>.from(bookings);
      _totalBookings = bookingsList.length;

      _statusCounts = {};
      _totalRevenue = 0;
      _thisMonthRevenue = 0;
      _lastMonthRevenue = 0;
      _thisMonthBookings = 0;
      _lastMonthBookings = 0;

      Map<String, int> serviceCounts = {};
      Map<String, double> monthlyRev = {};

      for (final b in bookingsList) {
        final status = b['status'] as String? ?? 'unknown';
        _statusCounts[status] = (_statusCounts[status] ?? 0) + 1;

        final price = (b['total_price'] as num?)?.toDouble() ?? 0;
        final created = b['created_at']?.toString().substring(0, 10) ?? '';
        final monthKey = created.length >= 7 ? created.substring(0, 7) : '';

        if (status == 'completed') {
          _totalRevenue += price;
          if (created.compareTo(thisMonthStart) >= 0) {
            _thisMonthRevenue += price;
          } else if (created.compareTo(lastMonthStart) >= 0 && created.compareTo(lastMonthEnd) <= 0) {
            _lastMonthRevenue += price;
          }
          if (monthKey.isNotEmpty) {
            monthlyRev[monthKey] = (monthlyRev[monthKey] ?? 0) + price;
          }
        }

        if (created.compareTo(thisMonthStart) >= 0) _thisMonthBookings++;
        if (created.compareTo(lastMonthStart) >= 0 && created.compareTo(lastMonthEnd) <= 0) _lastMonthBookings++;

        final sName = b['services']?['service_name'] ?? 'Unknown';
        serviceCounts[sName] = (serviceCounts[sName] ?? 0) + 1;
      }

      // Platform revenue = provider subscriptions only (no commission)
      _subscriptionRevenue = 0;
      try {
        final subs = await supabase.from('subscriptions').select('amount_paid');
        for (final s in List<Map<String, dynamic>>.from(subs)) {
          _subscriptionRevenue += (s['amount_paid'] as num?)?.toDouble() ?? 0;
        }
      } catch (_) {}

      // Monthly revenue sorted
      final sortedMonths = monthlyRev.entries.toList()
        ..sort((a, b) => b.key.compareTo(a.key));
      _monthlyRevenue = sortedMonths.take(6).map((e) => {'month': e.key, 'revenue': e.value}).toList();

      // Popular services
      final sortedServices = serviceCounts.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      _popularServices = sortedServices.take(5).map((e) => {'name': e.key, 'count': e.value}).toList();

      // Users
      final profiles = await supabase.from('profiles').select('user_type, is_verified, created_at');
      final profilesList = List<Map<String, dynamic>>.from(profiles);
      _totalUsers = profilesList.length;
      _totalProviders = profilesList.where((p) => p['user_type'] == 'provider').length;
      _verifiedProviders = profilesList.where((p) => p['user_type'] == 'provider' && p['is_verified'] == true).length;
      _newUsersThisMonth = profilesList.where((p) {
        final created = p['created_at']?.toString().substring(0, 10) ?? '';
        return created.compareTo(thisMonthStart) >= 0;
      }).length;

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  String _monthLabel(String monthKey) {
    final months = ['', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final parts = monthKey.split('-');
    if (parts.length != 2) return monthKey;
    final m = int.tryParse(parts[1]) ?? 0;
    return '${months[m]} ${parts[0]}';
  }

  double _growthPercent(double current, double previous) {
    if (previous == 0) return current > 0 ? 100 : 0;
    return ((current - previous) / previous * 100);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadAnalytics),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Revenue Overview
                    Text('Revenue', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _buildRevenueCard(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Monthly Revenue
                    if (_monthlyRevenue.isNotEmpty) ...[
                      Text('Monthly Revenue', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      _buildMonthlyRevenue(),
                      const SizedBox(height: AppSpacing.xxl),
                    ],

                    // Bookings Overview
                    Text('Bookings', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _buildBookingsCard(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Status Breakdown
                    Text('Booking Status Breakdown', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _buildStatusBreakdown(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Users
                    Text('Users', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.md),
                    _buildUsersCard(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Popular Services
                    if (_popularServices.isNotEmpty) ...[
                      Text('Popular Services', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.md),
                      _buildPopularServices(),
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildRevenueCard() {
    final revenueGrowth = _growthPercent(_thisMonthRevenue, _lastMonthRevenue);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Total Revenue', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'R${_totalRevenue.toStringAsFixed(0)}',
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _miniStat('This Month', 'R${_thisMonthRevenue.toStringAsFixed(0)}'),
              const SizedBox(width: AppSpacing.xxl),
              _miniStat('Subscriptions', 'R${_subscriptionRevenue.toStringAsFixed(0)}'),
              const SizedBox(width: AppSpacing.xxl),
              _miniStat(
                'Growth',
                '${revenueGrowth >= 0 ? '+' : ''}${revenueGrowth.toStringAsFixed(0)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _miniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
      ],
    );
  }

  Widget _buildMonthlyRevenue() {
    final maxRev = _monthlyRevenue.fold<double>(0, (max, m) => (m['revenue'] as double) > max ? m['revenue'] as double : max);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: _monthlyRevenue.map((m) {
          final rev = m['revenue'] as double;
          final pct = maxRev > 0 ? rev / maxRev : 0.0;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text(
                    _monthLabel(m['month']),
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: AppRadius.smAll,
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 24,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            borderRadius: AppRadius.smAll,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 70,
                  child: Text(
                    'R${rev.toStringAsFixed(0)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBookingsCard() {
    final bookingGrowth = _growthPercent(_thisMonthBookings.toDouble(), _lastMonthBookings.toDouble());

    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_totalBookings', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                const Text('Total Bookings', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    bookingGrowth >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                    color: bookingGrowth >= 0 ? AppColors.success : AppColors.error,
                    size: 18,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    '${bookingGrowth >= 0 ? '+' : ''}${bookingGrowth.toStringAsFixed(0)}%',
                    style: TextStyle(
                      color: bookingGrowth >= 0 ? AppColors.success : AppColors.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text('$_thisMonthBookings this month', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBreakdown() {
    final orderedStatuses = ['pending', 'confirmed', 'en_route', 'arrived', 'in_progress', 'completed', 'cancelled'];

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: orderedStatuses.where((s) => (_statusCounts[s] ?? 0) > 0).map((s) {
          final count = _statusCounts[s] ?? 0;
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color: StatusColors.background(s),
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$count',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: StatusColors.foreground(s)),
                ),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  StatusColors.label(s),
                  style: TextStyle(fontSize: 12, color: StatusColors.foreground(s), fontWeight: FontWeight.w500),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildUsersCard() {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xxl),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _userStatTile('Total', '$_totalUsers', Icons.people_rounded, AppColors.info),
              const SizedBox(width: AppSpacing.md),
              _userStatTile('Providers', '$_totalProviders', Icons.spa_rounded, AppColors.secondary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _userStatTile('Verified', '$_verifiedProviders', Icons.verified_rounded, AppColors.success),
              const SizedBox(width: AppSpacing.md),
              _userStatTile('New (month)', '$_newUsersThisMonth', Icons.person_add_rounded, AppColors.primary),
            ],
          ),
        ],
      ),
    );
  }

  Widget _userStatTile(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: AppRadius.mdAll,
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: color)),
                Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPopularServices() {
    final maxCount = _popularServices.fold<int>(0, (max, s) => (s['count'] as int) > max ? s['count'] as int : max);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: _popularServices.asMap().entries.map((entry) {
          final i = entry.key;
          final s = entry.value;
          final count = s['count'] as int;
          final pct = maxCount > 0 ? count / maxCount : 0.0;
          final colors = [AppColors.primary, AppColors.secondary, AppColors.accent, AppColors.info, AppColors.success];

          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Row(
              children: [
                SizedBox(
                  width: 20,
                  child: Text(
                    '${i + 1}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textTertiary),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    s['name'],
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      Container(
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          borderRadius: AppRadius.smAll,
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: pct,
                        child: Container(
                          height: 20,
                          decoration: BoxDecoration(
                            color: colors[i % colors.length].withValues(alpha: 0.3),
                            borderRadius: AppRadius.smAll,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 30,
                  child: Text(
                    '$count',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
