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

  Map<String, dynamic> _m(String k) => Map<String, dynamic>.from(_stats[k] as Map? ?? {});
  static int _n(dynamic v) => (v as num?)?.toInt() ?? 0;
  static String _money(num v) => '\$${v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2)}';

  /// Every admin tool, with how many things wait in it.
  List<_Tool> get _tools {
    final t = _m('todo');
    return [
      _Tool(TablerIcons.rosette_discount_check, 'Verifications', 'ID checks for pros', '/admin/verify', _n(t['verifications'])),
      _Tool(TablerIcons.flag, 'Disputes', 'Reports from clients and pros', '/admin/disputes', _n(t['disputes']),
          urgent: _n(t['sexual_conduct']) > 0),
      _Tool(TablerIcons.device_mobile_dollar, 'EcoCash fees', 'Subscription payments to confirm', '/admin/fees', _n(t['fees'])),
      _Tool(TablerIcons.building_store, 'Businesses', 'Business verifications', '/admin/business', _n(t['business'])),
      _Tool(TablerIcons.message_star, 'Reported reviews', 'Reviews flagged by pros', '/admin/moderation', _n(t['reported_reviews'])),
      _Tool(TablerIcons.shield_check, 'Flagged services', 'Services that need a look', '/admin/moderation?tab=flagged', _n(t['flagged_services'])),
      _Tool(TablerIcons.bug, 'App errors', 'Crashes reported by the app', '/admin/errors', _n(t['errors'])),
      _Tool(TablerIcons.users, 'Users', 'Search, ban, deactivate', '/admin/users', 0),
      _Tool(TablerIcons.calendar_month, 'Bookings', 'Every booking on BeauTap', '/admin/bookings', 0),
      _Tool(TablerIcons.chart_bar, 'Analytics', 'Growth, income, cities', '/admin/analytics', 0),
      _Tool(TablerIcons.map, 'Area demand', 'Where clients look for pros', '/admin/moderation?tab=demand', 0),
      _Tool(TablerIcons.sparkles, 'Tips & trends', 'Write, hide or show tips', '/tips', 0),
    ];
  }

  void _open(String route) => context.push(route).then((_) => _loadStats());

  @override
  Widget build(BuildContext context) {
    if (!_isAdmin) {
      return const Scaffold(body: LoadingPlaceholder(kind: PlaceholderKind.detail));
    }
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    final overview = _loading
        ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
        : RefreshIndicator.adaptive(
            onRefresh: _loadStats,
            child: ListView(
              padding: EdgeInsets.fromLTRB(wide ? 28 : 16, wide ? 24 : 8, wide ? 28 : 16, 32),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1100),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _overview(wide)),
                  ),
                ),
              ],
            ),
          );
    if (!wide) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin'),
          actions: [IconButton(tooltip: 'Refresh', icon: const Icon(TablerIcons.refresh), onPressed: _loadStats)],
        ),
        body: overview,
      );
    }
    return Scaffold(
      body: Row(children: [
        _Sidebar(tools: _tools, onOpen: _open, onRefresh: _loadStats),
        Expanded(child: overview),
      ]),
    );
  }

  List<Widget> _overview(bool wide) {
    final u = _m('users'), inc = _m('income');
    final waiting = _tools.where((t) => t.count > 0).toList();
    final total = waiting.fold<int>(0, (s, t) => s + t.count);
    final sexual = _n(_m('todo')['sexual_conduct']);
    final now = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

    final kpis = [
      _Kpi('Users', '$_totalUsers', '$_totalProviders pros · $_totalClients clients', () => _open('/admin/users')),
      _Kpi('Pros clients can find', '${_n(u['pros_findable'])}',
          _n(u['pros_no_location']) > 0 ? '${_n(u['pros_no_location'])} without a location' : 'of $_totalProviders pros',
          () => _open('/admin/users'), warn: _n(u['pros_no_location']) > 0),
      _Kpi('Bookings', '$_totalBookings', '$_completedBookings done · ${_money(_totalRevenue)} to pros', () => _open('/admin/bookings')),
      _Kpi('BeauTap income', _money(_subscriptionRevenue), '${_money((inc['this_month'] as num?) ?? 0)} this month',
          () => _open('/admin/analytics')),
    ];

    final attention = _Panel(
      title: 'Needs attention',
      trailing: total > 0 ? _CountPill(total, urgent: sexual > 0) : null,
      child: waiting.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Row(children: [
                Icon(TablerIcons.circle_check_filled, color: AppColors.success, size: 20),
                const SizedBox(width: 10),
                Text('All clear. Nothing is waiting for you.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
              ]),
            )
          : Column(children: [
              if (sexual > 0)
                _Row(
                  icon: TablerIcons.alert_triangle,
                  color: AppColors.error,
                  title: '$sexual sexual-conduct report${sexual == 1 ? '' : 's'}',
                  subtitle: 'Look at ${sexual == 1 ? 'this' : 'these'} first',
                  onTap: () => _open('/admin/disputes'),
                ),
              for (final t in waiting)
                _Row(
                  icon: t.icon,
                  title: t.label,
                  subtitle: t.subtitle,
                  count: t.count,
                  onTap: () => _open(t.route),
                ),
            ]),
    );

    final recent = _Panel(
      title: 'Recent bookings',
      action: 'View all',
      onAction: () => _open('/admin/bookings'),
      child: _recentBookings.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No bookings yet', style: TextStyle(color: AppColors.textSecondary)),
            )
          : Column(children: [
              for (final b in _recentBookings)
                _Row(
                  icon: TablerIcons.calendar_event,
                  title: b['services']?['service_name'] ?? 'Service',
                  subtitle: [b['profiles']?['full_name'] ?? 'Client', _when(b['booking_time'])].join(' · '),
                  trailingText: b['total_price'] == null ? null : _money(b['total_price'] as num),
                  status: b['status'] as String?,
                  onTap: () => _open('/booking/${b['id']}'),
                ),
            ]),
    );

    final top = _Panel(
      title: 'Top pros',
      child: _topProviders.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text('No reviews yet', style: TextStyle(color: AppColors.textSecondary)),
            )
          : Column(children: [
              for (final (i, p) in _topProviders.take(6).indexed)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: Row(children: [
                    SizedBox(
                      width: 22,
                      child: Text('${i + 1}',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: i < 3 ? AppColors.goldText : AppColors.textTertiary)),
                    ),
                    Expanded(
                      child: Text(p['name'], maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                    ),
                    Text('★ ${(p['rating'] as double).toStringAsFixed(1)}',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    SizedBox(
                      width: 78,
                      child: Text('${p['reviews']} ${p['reviews'] == 1 ? 'review' : 'reviews'}',
                          textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ),
                  ]),
                ),
            ]),
    );

    return [
      Text('${days[now.weekday - 1]} ${now.day} ${months[now.month - 1]}'.toUpperCase(),
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary)),
      const SizedBox(height: 4),
      Text('BeauTap admin',
          style: TextStyle(
              fontFamily: AppTheme.displayFamily, fontSize: wide ? 30 : 26, fontWeight: FontWeight.w700, letterSpacing: -0.5, color: AppColors.textPrimary)),
      const SizedBox(height: 16),
      _KpiStrip(kpis: kpis, wide: wide),
      const SizedBox(height: 16),
      if (wide)
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: attention),
          const SizedBox(width: 16),
          Expanded(flex: 4, child: top),
        ])
      else ...[attention, const SizedBox(height: 16), top],
      const SizedBox(height: 16),
      recent,
      if (!wide) ...[
        const SizedBox(height: 16),
        _Panel(
          title: 'All tools',
          child: Column(children: [
            for (final t in _tools)
              _Row(icon: t.icon, title: t.label, subtitle: t.subtitle, count: t.count, onTap: () => _open(t.route)),
          ]),
        ),
      ],
    ];
  }

  String _when(dynamic iso) {
    final d = DateTime.tryParse((iso ?? '').toString())?.toLocal();
    if (d == null) return '';
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${d.day} ${m[d.month - 1]}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }
}

class _Tool {
  final IconData icon;
  final String label;
  final String subtitle;
  final String route;
  final int count;
  final bool urgent;
  const _Tool(this.icon, this.label, this.subtitle, this.route, this.count, {this.urgent = false});
}

class _Kpi {
  final String label;
  final String value;
  final String sub;
  final VoidCallback onTap;
  final bool warn;
  const _Kpi(this.label, this.value, this.sub, this.onTap, {this.warn = false});
}

List<BoxShadow>? get _shadow => AppColors.isDark ? null : AppShadows.lifted;

/// One slim card with four numbers side by side (2 × 2 on phones).
class _KpiStrip extends StatelessWidget {
  final List<_Kpi> kpis;
  final bool wide;
  const _KpiStrip({required this.kpis, required this.wide});

  @override
  Widget build(BuildContext context) {
    Widget cell(_Kpi k) => InkWell(
          onTap: k.onTap,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k.label, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(height: 2),
              Text(k.value,
                  style: TextStyle(fontFamily: AppTheme.displayFamily, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(k.sub, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: k.warn ? AppColors.warningText : AppColors.textTertiary)),
            ]),
          ),
        );
    final divider = Container(width: 1, height: 44, color: AppColors.border);
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
      child: wide
          ? Row(children: [
              for (final (i, k) in kpis.indexed) ...[if (i > 0) divider, Expanded(child: cell(k))],
            ])
          : Column(children: [
              Row(children: [Expanded(child: cell(kpis[0])), divider, Expanded(child: cell(kpis[1]))]),
              Divider(height: 1, color: AppColors.border),
              Row(children: [Expanded(child: cell(kpis[2])), divider, Expanded(child: cell(kpis[3]))]),
            ]),
    );
  }
}

class _Panel extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;
  final String? action;
  final VoidCallback? onAction;
  const _Panel({required this.title, required this.child, this.trailing, this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
          const Spacer(),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                  minimumSize: const Size(0, 32), tapTargetSize: MaterialTapTargetSize.shrinkWrap, foregroundColor: AppColors.goldText),
              child: Text(action!),
            ),
        ]),
        const SizedBox(height: 4),
        child,
      ]),
    );
  }
}

class _CountPill extends StatelessWidget {
  final int n;
  final bool urgent;
  const _CountPill(this.n, {this.urgent = false});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(color: urgent ? AppColors.error : AppColors.gold, borderRadius: AppRadius.pill),
        child: Text('$n',
            style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: urgent ? Colors.white : const Color(0xFF17130E))),
      );
}

/// A slim list row: icon, title, subtitle, and a count or amount.
class _Row extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final int count;
  final String? trailingText;
  final String? status;
  final Color? color;
  final VoidCallback onTap;
  const _Row({
    required this.icon,
    required this.title,
    this.subtitle,
    this.count = 0,
    this.trailingText,
    this.status,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textSecondary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color != null ? color!.withValues(alpha: 0.12) : AppColors.surfaceMuted,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 17, color: color ?? AppColors.textPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: color ?? AppColors.textPrimary)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ]),
          ),
          if (status != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: StatusColors.background(status!), borderRadius: AppRadius.pill),
              child: Text(StatusColors.label(status!),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: StatusColors.foreground(status!))),
            ),
            const SizedBox(width: 8),
          ],
          if (trailingText != null)
            Text(trailingText!, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          if (count > 0) _CountPill(count),
          const SizedBox(width: 4),
          Icon(TablerIcons.chevron_right, size: 16, color: c.withValues(alpha: 0.6)),
        ]),
      ),
    );
  }
}

/// Laptop: the admin tools down the left, with counts.
class _Sidebar extends StatelessWidget {
  final List<_Tool> tools;
  final void Function(String) onOpen;
  final VoidCallback onRefresh;
  const _Sidebar({required this.tools, required this.onOpen, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    final bg = dark ? const Color(0xFF12100E) : const Color(0xFF141210);
    Widget item(IconData icon, String label, {int count = 0, bool selected = false, VoidCallback? onTap}) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Material(
            color: selected ? AppColors.gold : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: onTap,
              child: SizedBox(
                height: 40,
                child: Row(children: [
                  const SizedBox(width: 12),
                  Icon(icon, size: 18, color: selected ? const Color(0xFF17130E) : const Color(0xFFCFC6B8)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                            color: selected ? const Color(0xFF17130E) : const Color(0xFFE8E0D2))),
                  ),
                  if (count > 0)
                    Container(
                      margin: const EdgeInsets.only(right: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
                      decoration: BoxDecoration(color: AppColors.gold, borderRadius: AppRadius.pill),
                      child: Text('$count',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
                    ),
                ]),
              ),
            ),
          ),
        );
    final queue = tools.where((t) => t.count > 0 || t.route.startsWith('/admin/verify') || t.route.startsWith('/admin/disputes')).take(7).toList();
    final rest = tools.where((t) => !queue.contains(t)).toList();
    Widget heading(String t) => Padding(
          padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
          child: Text(t.toUpperCase(),
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 1, color: Color(0xFF8F877B))),
        );
    return Container(
      width: 248,
      color: bg,
      child: SafeArea(
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 16, 12, 16), children: [
          Row(children: [
            const SizedBox(width: 4),
            Image.asset('assets/branding/app_mark.png', width: 32, height: 32),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('BeauTap', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: Color(0xFFF5EFE6))),
                Text('Admin', style: TextStyle(fontSize: 12, color: AppColors.gold)),
              ]),
            ),
            IconButton(
              tooltip: 'Refresh',
              onPressed: onRefresh,
              icon: const Icon(TablerIcons.refresh, size: 18, color: Color(0xFFCFC6B8)),
            ),
          ]),
          const SizedBox(height: 12),
          item(TablerIcons.layout_dashboard, 'Overview', selected: true),
          heading('To review'),
          for (final t in queue) item(t.icon, t.label, count: t.count, onTap: () => onOpen(t.route)),
          heading('Manage'),
          for (final t in rest) item(t.icon, t.label, count: t.count, onTap: () => onOpen(t.route)),
          heading('Back to the app'),
          item(TablerIcons.arrow_back_up, 'Leave admin', onTap: () => context.canPop() ? context.pop() : context.go('/home')),
        ]),
      ),
    );
  }
}
