import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/smart_match_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});
  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  bool _isAdmin = false;
  bool _loading = true;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _topStylists = [];
  Map<String, dynamic>? _nextBooking;
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


    int unreadNotifs = 0;
    try {
      unreadNotifs = await NotificationService.unreadCount(userId);
    } catch (_) {}

    List<Map<String, dynamic>> categories = [];
    List<Map<String, dynamic>> stylists = [];
    Map<String, dynamic>? nextBooking;
    try {
      final results = await Future.wait([
        supabase.from('service_categories').select('id, name, icon, sort_order').order('sort_order', ascending: true),
        SmartMatchService.getTopRated(location: profile['location'], limit: 8),
        supabase
            .from('bookings')
            .select('id, booking_time, status, services(service_name), profiles!bookings_provider_id_fkey(full_name)')
            .eq('client_id', userId)
            .inFilter('status', ['pending', 'confirmed'])
            .gte('booking_time', DateTime.now().toUtc().toIso8601String())
            .order('booking_time')
            .limit(1),
      ]);
      categories = List<Map<String, dynamic>>.from(results[0] as List);
      stylists = List<Map<String, dynamic>>.from(results[1] as List);
      bool featured(Map<String, dynamic> p) =>
          DateTime.tryParse((p['featured_until'] ?? '').toString())?.isAfter(DateTime.now()) ?? false;
      stylists.sort((a, b) => (featured(b) ? 1 : 0).compareTo(featured(a) ? 1 : 0));
      final nb = results[2] as List;
      nextBooking = nb.isNotEmpty ? nb.first as Map<String, dynamic> : null;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _profile = profile;
        _isAdmin = isAdmin;
        _unreadNotifications = unreadNotifs;
        _categories = categories;
        _topStylists = stylists;
        _nextBooking = nextBooking;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  String get _greeting {
    final h = DateTime.now().hour;
    if (h < 12) return 'Good morning';
    if (h < 17) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name = (_profile?['full_name'] ?? '').toString();
    final firstName = name.split(' ').first;
    final isGuest = supabase.auth.currentUser?.isAnonymous ?? false;

    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadData,
          child: FadeTransition(
            opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    // Header
                    Row(children: [
                      GestureDetector(
                        onTap: () => context.push('/account/settings'),
                        child: PersonAvatar(name: name, url: _profile?['avatar_url'], size: 46),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(_greeting, style: Theme.of(context).textTheme.bodyMedium),
                          Text(
                            firstName.isEmpty || isGuest || firstName == 'User' ? 'Welcome' : firstName,
                            style: Theme.of(context).textTheme.titleLarge,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ]),
                      ),
                      if (_isAdmin)
                        _RoundIcon(
                          icon: Icons.admin_panel_settings_outlined,
                          tooltip: 'Admin',
                          onTap: () => context.push('/admin/dashboard'),
                        ),
                      const SizedBox(width: 8),
                      _RoundIcon(
                        icon: Icons.notifications_none_rounded,
                        tooltip: 'Notifications',
                        badge: _unreadNotifications,
                        onTap: () async {
                          await context.push('/notifications');
                          _loadData();
                        },
                      ),
                      const SizedBox(width: 8),
                      PopupMenuButton<String>(
                        tooltip: 'Menu',
                        icon: const Icon(Icons.more_horiz_rounded),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                        onSelected: (v) {
                          if (v == 'settings') context.push('/account/settings');
                          if (v == 'signout') _signOut();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'settings', child: Text('Account settings')),
                          PopupMenuItem(value: 'signout', child: Text('Sign out')),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 24),

                    Text('What would you like\ndone today?',
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 16),

                    // Search
                    Material(
                      color: Colors.white,
                      borderRadius: AppRadius.lgAll,
                      child: InkWell(
                        borderRadius: AppRadius.lgAll,
                        onTap: () => context.go('/browse'),
                        child: Container(
                          height: 56,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.lgAll,
                            border: Border.all(color: AppColors.border),
                            boxShadow: AppShadows.soft,
                          ),
                          child: Row(children: [
                            const Icon(Icons.search_rounded, color: AppColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text('Search braids, nails, makeup…',
                                  style: Theme.of(context).textTheme.bodyMedium),
                            ),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: AppColors.primarySoft,
                                borderRadius: AppRadius.smAll,
                              ),
                              child: const Icon(Icons.tune_rounded, size: 18, color: AppColors.primary),
                            ),
                          ]),
                        ),
                      ),
                    ),

                    if (isGuest) ...[
                      const SizedBox(height: 16),
                      SoftBanner(
                        icon: Icons.bookmark_add_outlined,
                        color: AppColors.primary,
                        title: 'You\'re browsing as a guest',
                        message: 'Create a free account to keep your bookings on any phone.',
                        actionLabel: 'Create',
                        onTap: () => context.push('/account/settings'),
                      ),
                    ],

                    // Next appointment
                    if (_nextBooking != null) ...[
                      const SizedBox(height: 24),
                      const SectionHeader(title: 'Your next appointment'),
                      _NextBookingCard(booking: _nextBooking!),
                    ],

                    // Categories
                    if (_categories.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      SectionHeader(
                        title: 'Categories',
                        actionLabel: 'See all',
                        onAction: () => context.go('/browse'),
                      ),
                      SizedBox(
                        height: 96,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _categories.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) {
                            final c = _categories[i];
                            return _CategoryChip(
                              icon: categoryIcon(c['name']),
                              label: c['name'] ?? '',
                              onTap: () {
                                BrowseIntent.category.value = c['id'];
                                context.go('/browse');
                              },
                            );
                          },
                        ),
                      ),
                    ],

                    // Shortcuts
                    const SizedBox(height: 24),
                    Row(children: [
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.person_outline_rounded,
                          label: 'Account',
                          onTap: () => context.push('/account/settings'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.event_note_rounded,
                          label: 'Bookings',
                          onTap: () => context.go('/client/bookings'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.favorite_border_rounded,
                          label: 'Saved',
                          onTap: () => context.go('/favorites'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Shortcut(
                          icon: Icons.campaign_outlined,
                          label: 'Requests',
                          onTap: () => context.push('/service-requests'),
                        ),
                      ),
                    ]),

                    // Request card
                    const SizedBox(height: 24),
                    _RequestCard(
                      onTap: () => context.push('/service-request/create'),
                    ),

                    // Top stylists
                    if (_topStylists.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      SectionHeader(
                        title: 'Top rated near you',
                        actionLabel: 'Browse',
                        onAction: () => context.go('/browse'),
                      ),
                      SizedBox(
                        height: 204,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: _topStylists.length,
                          separatorBuilder: (_, __) => const SizedBox(width: 12),
                          itemBuilder: (_, i) => _StylistCard(provider: _topStylists[i]),
                        ),
                      ),
                    ],

                    if (_nextBooking == null) ...[
                      const SizedBox(height: 28),
                      const SectionHeader(title: 'How BeauTap works'),
                      const _HowItWorks(),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final int badge;
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap, this.badge = 0});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white,
        shape: const CircleBorder(side: BorderSide(color: AppColors.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Badge(
              isLabelVisible: badge > 0,
              label: Text(badge > 9 ? '9+' : '$badge'),
              offset: const Offset(4, -4),
              child: Icon(icon, size: 22, color: AppColors.textPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _CategoryChip({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgAll,
      child: SizedBox(
        width: 76,
        child: Column(children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: AppColors.border),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 26, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

class _Shortcut extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _Shortcut({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.lgAll,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Icon(icon, color: AppColors.primary, size: 24),
            const SizedBox(height: 6),
            Text(label,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          ]),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RequestCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: AppRadius.xlAll,
      ),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Can\'t find what you need?',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.3)),
            const SizedBox(height: 6),
            Text('Post a request and stylists send you their best price.',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: Colors.white.withValues(alpha: 0.85))),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: onTap,
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: AppColors.primary,
                minimumSize: const Size(0, 42),
                padding: const EdgeInsets.symmetric(horizontal: 18),
              ),
              child: const Text('Post a request'),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.campaign_rounded, color: Colors.white, size: 32),
        ),
      ]),
    );
  }
}

class _NextBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _NextBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final dt = DateTime.tryParse(booking['booking_time'] ?? '')?.toLocal();
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final confirmed = booking['status'] == 'confirmed';
    return Card(
      child: InkWell(
        onTap: () => context.push('/booking/${booking['id']}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Container(
              width: 58,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
              child: Column(children: [
                Text(dt != null ? months[dt.month - 1] : '',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text(dt != null ? '${dt.day}' : '--',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.1)),
              ]),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(booking['services']?['service_name'] ?? 'Appointment',
                    style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  '${dt != null ? '${days[dt.weekday - 1]} · ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}' : ''}'
                  ' with ${booking['profiles']?['full_name'] ?? 'your stylist'}',
                  style: Theme.of(context).textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Pill(
                  label: confirmed ? 'Confirmed' : 'Waiting for stylist',
                  color: confirmed ? AppColors.success : AppColors.warning,
                ),
              ]),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ]),
        ),
      ),
    );
  }
}

class _StylistCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  const _StylistCard({required this.provider});

  @override
  Widget build(BuildContext context) {
    final name = provider['profiles']?['full_name'] ?? 'Stylist';
    final location = (provider['profiles']?['location'] ?? '').toString();
    final rating = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final available = provider['availability_status'] == 'available';
    return SizedBox(
      width: 156,
      child: Card(
        child: InkWell(
          onTap: () => context.push('/provider/${provider['provider_id']}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Stack(children: [
                PersonAvatar(name: name, url: provider['profiles']?['avatar_url'], size: 56),
                if (available)
                  Positioned(
                    right: 2,
                    bottom: 2,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: AppColors.available,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 12),
              Text(name, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(location.isEmpty ? 'Zimbabwe' : location,
                  style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
              const Spacer(),
              if (DateTime.tryParse((provider['featured_until'] ?? '').toString())?.isAfter(DateTime.now()) ?? false)
                const Padding(
                  padding: EdgeInsets.only(bottom: 6),
                  child: Pill(label: 'Featured', color: AppColors.secondary, icon: Icons.star_rounded),
                ),
              RatingPill(rating: rating, reviews: reviews),
            ]),
          ),
        ),
      ),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (Icons.search_rounded, 'Find a stylist', 'Browse verified stylists, prices and real reviews.'),
      (Icons.event_available_rounded, 'Book a time', 'Pick a slot that suits you — pay cash, EcoCash or card.'),
      (Icons.home_rounded, 'Relax at home', 'Your stylist comes to you. Rate them afterwards.'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < steps.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                  child: Icon(steps[i].$1, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$2, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(steps[i].$3, style: Theme.of(context).textTheme.bodyMedium),
                  ]),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }
}
