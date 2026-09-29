import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/smart_match_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../widgets/location_picker_sheet.dart';
import '../widgets/product_feed.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  List<Map<String, dynamic>> _topStylists = [];
  Map<String, dynamic>? _nextBooking;
  late AnimationController _animCtrl;

  /// City chosen in the picker (shared with Browse).
  String _city = 'All Zimbabwe';

  Future<void> _loadCity() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final c = prefs.getString('selected_city');
      if (c != null && mounted) setState(() => _city = c);
    } catch (_) {}
  }

  void _pickCity() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true, // above the bottom tab bar
      showDragHandle: false, // the sheet draws its own
      backgroundColor: Colors.transparent,
      builder: (_) => LocationPickerSheet(
        currentCity: _city,
        onCitySelected: (city, lat, lng) {
          if (mounted) setState(() => _city = city);
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _loadData();
    _loadCity();
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

    List<Map<String, dynamic>> stylists = [];
    Map<String, dynamic>? nextBooking;
    try {
      final results = await Future.wait([
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
      stylists = List<Map<String, dynamic>>.from(results[0] as List);
      bool featured(Map<String, dynamic> p) =>
          DateTime.tryParse((p['featured_until'] ?? '').toString())?.isAfter(DateTime.now()) ?? false;
      stylists.sort((a, b) => (featured(b) ? 1 : 0).compareTo(featured(a) ? 1 : 0));
      final nb = results[1] as List;
      nextBooking = nb.isNotEmpty ? nb.first as Map<String, dynamic> : null;
    } catch (_) {}

    if (mounted) {
      setState(() {
        _profile = profile;
        _isAdmin = isAdmin;
        _unreadNotifications = unreadNotifs;
        _topStylists = stylists;
        _nextBooking = nextBooking;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingPlaceholder());
    }

    final name = (_profile?['full_name'] ?? '').toString();
    final firstName = name.split(' ').first;
    final isGuest = supabase.auth.currentUser?.isAnonymous ?? false;


    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _loadData,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            children: [
              ForestHeader(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 640),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            InkWell(
                              onTap: _pickCity,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const Icon(TablerIcons.map_pin, color: AppColors.goldLight, size: 18),
                                  const SizedBox(width: 4),
                                  Text(_city == 'All Zimbabwe' ? 'All Zimbabwe' : _city,
                                      style: const TextStyle(
                                          color: AppColors.goldLight, fontSize: 15, fontWeight: FontWeight.w700)),
                                  const SizedBox(width: 2),
                                  const Icon(TablerIcons.chevron_down, color: AppColors.goldLight, size: 16),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              firstName.isEmpty || isGuest || firstName == 'User' ? 'Welcome' : 'Hi $firstName',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: -0.4),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ]),
                        ),
                        if (_isAdmin) ...[
                          _RoundIcon(
                            icon: TablerIcons.shield_lock,
                            tooltip: 'Admin',
                            onTap: () => context.push('/admin/dashboard'),
                          ),
                          const SizedBox(width: 8),
                        ],
                        _RoundIcon(
                          icon: TablerIcons.bell,
                          tooltip: 'Notifications',
                          badge: _unreadNotifications,
                          onTap: () async {
                            await context.push('/notifications');
                            _loadData();
                          },
                        ),
                        const SizedBox(width: 8),
                        _RoundIcon(
                          icon: TablerIcons.user,
                          tooltip: 'Account',
                          onTap: () => context.push('/account/settings'),
                        ),
                      ]),
                      const SizedBox(height: 16),
                      Material(
                        color: AppColors.card,
                        borderRadius: AppRadius.mdAll,
                        child: InkWell(
                          borderRadius: AppRadius.mdAll,
                          onTap: () => context.go('/browse'),
                          child: SizedBox(
                            height: 52,
                            child: Row(children: [
                              SizedBox(width: 14),
                              Icon(TablerIcons.search, color: AppColors.textPrimary, size: 22),
                              SizedBox(width: 10),
                              Expanded(
                                child: Text('Braids, fade, gel nails…',
                                    style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                              ),
                            ]),
                          ),
                        ),
                      ),
                    ]),
                  ),
                ),
              ),
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (isGuest) ...[
                        SoftBanner(
                          icon: TablerIcons.bookmark_plus,
                          color: AppColors.primary,
                          title: 'You\'re browsing as a guest',
                          message: 'Create a free account to keep your bookings on any phone.',
                          actionLabel: 'Create',
                          onTap: () => context.push('/account/settings'),
                        ),
                        const SizedBox(height: 20),
                      ],
                      if (_nextBooking != null) ...[
                        const SectionHeader(title: 'Your next appointment'),
                        _NextBookingCard(booking: _nextBooking!),
                        const SizedBox(height: 20),
                      ],
                      const SectionHeader(title: 'Services'),
                      LayoutBuilder(builder: (context, c) {
                        final cols = c.maxWidth > 520 ? 6 : 4;
                        return Wrap(
                          runSpacing: 14,
                          children: [
                            for (final g in ServiceGroup.all)
                              SizedBox(
                                width: c.maxWidth / cols,
                                child: _CategoryChip(
                                  icon: g.icon,
                                  label: g.name,
                                  onTap: () {
                                    BrowseIntent.group.value = g.name;
                                    context.go('/browse');
                                  },
                                ),
                              ),
                          ],
                        );
                      }),
                      const SizedBox(height: 24),
                      ProductFeedSection(city: _city),
                      if (_topStylists.isNotEmpty) ...[
                                                SectionHeader(
                          title: 'Featured near you',
                          actionLabel: 'See all',
                          onAction: () => context.go('/browse'),
                        ),
                        SizedBox(
                          height: 236,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: _topStylists.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 12),
                            itemBuilder: (_, i) => _StylistCard(provider: _topStylists[i]),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      _RequestCard(onTap: () => context.push('/service-request/create')),
                      if (_nextBooking == null) ...[
                        const SizedBox(height: 24),
                        const SectionHeader(title: 'How BeauTap works'),
                        const _HowItWorks(),
                      ],
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Square tile on the forest header (notifications, account).
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
        color: AppColors.pine,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: onTap,
          child: SizedBox(
            width: 48,
            height: 48,
            child: Stack(alignment: Alignment.center, children: [
              Icon(icon, size: 22, color: Colors.white),
              if (badge > 0)
                Positioned(
                  right: 11,
                  top: 11,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.pine, width: 1.5),
                    ),
                  ),
                ),
            ]),
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
      borderRadius: AppRadius.mdAll,
      child: Column(children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(14)),
          alignment: Alignment.center,
          child: Icon(icon, size: 24, color: AppColors.primary),
        ),
        const SizedBox(height: 6),
        Text(label,
            maxLines: 2,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, height: 1.2, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
      ]),
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
            Text('Post a request and beauty pros send you their best price.',
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
          child: const Icon(TablerIcons.speakerphone, color: Colors.white, size: 32),
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
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary)),
                Text(dt != null ? '${dt.day}' : '--',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1.1)),
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
                  ' with ${booking['profiles']?['full_name'] ?? 'your pro'}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 8),
                Pill(
                  label: confirmed ? 'Confirmed' : 'Waiting for pro',
                  color: confirmed ? AppColors.success : AppColors.warning,
                ),
              ]),
            ),
            Icon(TablerIcons.chevron_right, color: AppColors.textTertiary),
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
    final name = provider['profiles']?['full_name'] ?? 'Beauty pro';
    final location = (provider['profiles']?['location'] ?? '').toString();
    final rating = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final featured = DateTime.tryParse((provider['featured_until'] ?? '').toString())?.isAfter(DateTime.now()) ?? false;
    final avatar = provider['profiles']?['avatar_url'] as String?;
    return SizedBox(
      width: 200,
      child: Material(
        color: AppColors.card,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/provider/${provider['provider_id']}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              height: 128,
              width: double.infinity,
              child: Stack(fit: StackFit.expand, children: [
                if (avatar != null && avatar.isNotEmpty)
                  Image.network(avatar, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const _PhotoPlaceholder())
                else
                  const _PhotoPlaceholder(),
                if (featured)
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Pill(label: 'Featured', color: AppColors.gold, solid: true),
                  ),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name,
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(location.isEmpty ? 'Zimbabwe' : location,
                    style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                RatingPill(rating: rating, reviews: reviews),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();
  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: Icon(TablerIcons.photo, color: AppColors.textTertiary, size: 28),
    );
  }
}

class _HowItWorks extends StatelessWidget {
  const _HowItWorks();

  @override
  Widget build(BuildContext context) {
    const steps = [
      (TablerIcons.search, 'Find a beauty pro', 'Browse verified pros, prices and real reviews.'),
      (TablerIcons.calendar_check, 'Book a time', 'Pick a slot that suits you — pay cash, EcoCash or card.'),
      (TablerIcons.home, 'Get it done', 'At your place or theirs. Rate them afterwards.'),
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
                  decoration: BoxDecoration(color: AppColors.primarySoft, shape: BoxShape.circle),
                  child: Icon(steps[i].$1, color: AppColors.primary, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(steps[i].$2, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(steps[i].$3, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
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
