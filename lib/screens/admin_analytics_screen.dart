import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

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

  Map<String, dynamic> _income = {};
  double _paidToPros = 0;

  Future<void> _loadAnalytics() async {
    setState(() => _loading = true);
    try {
      final st = Map<String, dynamic>.from(await supabase.rpc('admin_stats') as Map);
      final b = Map<String, dynamic>.from(st['bookings'] as Map);
      final u = Map<String, dynamic>.from(st['users'] as Map);
      int n(dynamic v) => (v as num?)?.toInt() ?? 0;
      double d(dynamic v) => (v as num?)?.toDouble() ?? 0;

      _income = Map<String, dynamic>.from(st['income'] as Map);
      _totalRevenue = d(_income['total']);
      _thisMonthRevenue = d(_income['this_month']);
      _lastMonthRevenue = d(_income['last_month']);
      _subscriptionRevenue = d(_income['plans']);
      _paidToPros = d(b['completed_value']);

      _totalBookings = n(b['total']);
      _thisMonthBookings = n(b['this_month']);
      _lastMonthBookings = n(b['last_month']);
      _statusCounts = {
        for (final k in ['pending', 'confirmed', 'completed', 'cancelled'])
          if (n(b[k]) > 0) k: n(b[k]),
      };
      _monthlyRevenue = [
        for (final m in (st['income_by_month'] as List? ?? [])) {'month': m['month'], 'revenue': d(m['amount'])}
      ];
      _popularServices = [
        for (final p in (st['popular_services'] as List? ?? [])) {'name': p['name'], 'count': n(p['count'])}
      ];
      _totalUsers = n(u['total']);
      _totalProviders = n(u['providers']);
      _verifiedProviders = n(u['verified_providers']);
      _newUsersThisMonth = n(u['new_this_month']);

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  static String _money(num v) => '\$${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

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
          IconButton(icon: const Icon(TablerIcons.refresh), onPressed: _loadAnalytics),
        ],
      ),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : RefreshIndicator(
              onRefresh: _loadAnalytics,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: AppSpacing.screenPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Revenue Overview
                    Text('BeauTap income', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('What pros paid BeauTap: plans, featured spots and product ads.',
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.md),
                    _buildRevenueCard(),
                    const SizedBox(height: AppSpacing.xxl),

                    // Monthly Revenue
                    if (_monthlyRevenue.isNotEmpty) ...[
                      Text('Income by month', style: Theme.of(context).textTheme.titleMedium),
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
          const Text('All time', style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: AppSpacing.xs),
          Text(
            _money(_totalRevenue),
            style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              _miniStat('This month', _money(_thisMonthRevenue)),
              const SizedBox(width: AppSpacing.xl),
              _miniStat('Last month', _money(_lastMonthRevenue)),
              const SizedBox(width: AppSpacing.xl),
              if (_lastMonthRevenue > 0)
                _miniStat('Change', '${revenueGrowth >= 0 ? '+' : ''}${revenueGrowth.toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.xl, runSpacing: AppSpacing.sm, children: [
            _miniStat('Plans', _money(_subscriptionRevenue)),
            _miniStat('Featured', _money((_income['featured'] as num?) ?? 0)),
            _miniStat('Product ads', _money((_income['products'] as num?) ?? 0)),
            _miniStat('Paynow', _money((_income['paynow'] as num?) ?? 0)),
            _miniStat('EcoCash (manual)', _money((_income['ecocash_manual'] as num?) ?? 0)),
          ]),
          const SizedBox(height: AppSpacing.md),
          Text('Clients paid pros ${_money(_paidToPros)} for completed bookings (not BeauTap income).',
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
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
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
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
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Container(
                        height: 24,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceMuted,
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
                    _money(rev),
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
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$_totalBookings', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700)),
                Text('Total Bookings', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
                    bookingGrowth >= 0 ? TablerIcons.trending_up : TablerIcons.trending_down,
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
              Text('$_thisMonthBookings this month · $_lastMonthBookings last month',
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
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
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _userStatTile('Total', '$_totalUsers', TablerIcons.users, AppColors.info),
              const SizedBox(width: AppSpacing.md),
              _userStatTile('Providers', '$_totalProviders', TablerIcons.leaf, AppColors.secondary),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              _userStatTile('Verified', '$_verifiedProviders', TablerIcons.rosette_discount_check, AppColors.success),
              const SizedBox(width: AppSpacing.md),
              _userStatTile('New (month)', '$_newUsersThisMonth', TablerIcons.user_plus, AppColors.primary),
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
                Text(label, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textTertiary),
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
                          color: AppColors.surfaceMuted,
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
