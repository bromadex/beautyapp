import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../services/smart_match_service.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../utils/pro_photos.dart';
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
  Map<String, String> _covers = {};
  Set<String> _homeVisitPros = {};
  Set<String> _favourites = {};
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
    var covers = <String, String>{};
    var homeVisit = <String>{};
    var favourites = <String>{};
    try {
      final extras = await Future.wait<dynamic>([
        loadCoverPhotos(),
        supabase.from('services').select('provider_id').eq('is_active', true).inFilter('location_mode', ['client', 'either']),
        supabase.from('favorites').select('provider_id').eq('client_id', userId),
      ]);
      covers = extras[0] as Map<String, String>;
      homeVisit = {for (final r in extras[1] as List) r['provider_id'] as String};
      favourites = {for (final r in extras[2] as List) r['provider_id'] as String};
    } catch (_) {}
    try {
      final results = await Future.wait([
        SmartMatchService.getTopRated(location: profile['location'], limit: 12),
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
        _covers = covers;
        _homeVisitPros = homeVisit;
        _favourites = favourites;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  Future<void> _toggleFavourite(String providerId) async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    final saved = _favourites.contains(providerId);
    Haptics.firm();
    setState(() => saved ? _favourites.remove(providerId) : _favourites.add(providerId));
    try {
      if (saved) {
        await supabase.from('favorites').delete().eq('client_id', uid).eq('provider_id', providerId);
      } else {
        await supabase.from('favorites').insert({'client_id': uid, 'provider_id': providerId});
      }
    } catch (_) {
      // Put it back if the change did not save.
      if (mounted) setState(() => saved ? _favourites.add(providerId) : _favourites.remove(providerId));
    }
  }

  String get _greeting {
    final h = DateTime.now().hour;
    return h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
  }

  Widget _proRow(String title, List<Map<String, dynamic>> pros) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, actionLabel: 'See all', onAction: () => context.go('/browse')),
          SizedBox(
            height: 246,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              clipBehavior: Clip.none,
              itemCount: pros.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) {
                final p = pros[i];
                final id = p['provider_id'] as String;
                return _StylistCard(
                  provider: p,
                  photo: coverFor(_covers, id, p['profiles']?['avatar_url'] as String?),
                  saved: _favourites.contains(id),
                  onSave: () => _toggleFavourite(id),
                );
              },
            ),
          ),
          const SizedBox(height: 22),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: LoadingPlaceholder());
    }

    final name = (_profile?['full_name'] ?? '').toString();
    final firstName = name.split(' ').first;
    final isGuest = supabase.auth.currentUser?.isAnonymous ?? false;
    final showName = !(firstName.isEmpty || isGuest || firstName == 'User');
    final comesToYou = _topStylists.where((p) => _homeVisitPros.contains(p['provider_id'])).toList();

    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: _loadData,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + 10, 20, tabBarSpace(context)),
            children: [
              PageWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  // Greeting: your photo, the time of day, your city.
                  Row(children: [
                    GestureDetector(
                      onTap: () => context.push('/account/settings'),
                      child: Semantics(
                        button: true,
                        label: 'Account',
                        child: PersonAvatar(name: showName ? name : 'Guest', url: _profile?['avatar_url'] as String?, size: 46),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        InkWell(
                          onTap: _pickCity,
                          borderRadius: AppRadius.smAll,
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Text('$_greeting · ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            Icon(TablerIcons.map_pin, size: 14, color: AppColors.goldText),
                            Flexible(
                              child: Text(_city,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.goldText)),
                            ),
                            Icon(TablerIcons.chevron_down, size: 14, color: AppColors.goldText),
                          ]),
                        ),
                        Text(showName ? firstName : 'Welcome',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, letterSpacing: -0.3, color: AppColors.textPrimary)),
                      ]),
                    ),
                    if (_isAdmin) ...[
                      _RoundIcon(icon: TablerIcons.shield_lock, tooltip: 'Admin', onTap: () => context.push('/admin/dashboard')),
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
                  ]),
                  const SizedBox(height: 18),
                  // Search, with its own filter button.
                  Material(
                    color: AppColors.card,
                    borderRadius: BorderRadius.circular(28),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(28),
                      onTap: () => context.go('/browse'),
                      child: SizedBox(
                        height: 54,
                        child: Row(children: [
                          const SizedBox(width: 18),
                          Icon(TablerIcons.search, color: AppColors.textSecondary, size: 21),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text('Braids, fade, gel nails…',
                                style: TextStyle(fontSize: 15.5, color: AppColors.textSecondary)),
                          ),
                          Container(
                            width: 42,
                            height: 42,
                            margin: const EdgeInsets.only(right: 6),
                            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                            child: const Icon(TablerIcons.adjustments_horizontal, size: 20, color: Color(0xFF17130E)),
                          ),
                        ]),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _RequestCard(onTap: () => context.push('/service-request/create')),
                  if (isGuest) ...[
                    const SizedBox(height: 16),
                    SoftBanner(
                      icon: TablerIcons.bookmark_plus,
                      color: AppColors.goldText,
                      title: 'You\'re browsing as a guest',
                      message: 'Create a free account to keep your bookings on any phone.',
                      actionLabel: 'Create',
                      onTap: () => context.push('/account/settings'),
                    ),
                  ],
                  if (_nextBooking != null) ...[
                    const SizedBox(height: 22),
                    const SectionHeader(title: 'Your next appointment'),
                    _NextBookingCard(booking: _nextBooking!),
                  ],
                  const SizedBox(height: 22),
                  SectionHeader(title: 'Categories', actionLabel: 'See all', onAction: () => context.go('/browse')),
                  SizedBox(
                    height: 46,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      clipBehavior: Clip.none,
                      children: [
                        _PhotoChip(
                          label: 'All',
                          selected: true,
                          onTap: () {
                            Haptics.light();
                            BrowseIntent.group.value = null;
                            context.go('/browse');
                          },
                        ),
                        for (final g in ServiceGroup.all)
                          _PhotoChip(
                            label: g.name,
                            photo: g.photo,
                            onTap: () {
                              Haptics.light();
                              BrowseIntent.group.value = g.name;
                              context.go('/browse');
                            },
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 22),
                  if (_topStylists.isNotEmpty) _proRow('Near you', _topStylists),
                  if (comesToYou.isNotEmpty) _proRow('Comes to you', comesToYou),
                  ProductFeedSection(city: _city),
                  if (_nextBooking == null) ...[
                    const SizedBox(height: 8),
                    const SectionHeader(title: 'How BeauTap works'),
                    const _HowItWorks(),
                  ],
                  const SizedBox(height: 12),
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Category chip with a small round photo; "All" is filled gold.
class _PhotoChip extends StatelessWidget {
  final String label;
  final String? photo;
  final bool selected;
  final VoidCallback onTap;
  const _PhotoChip({required this.label, required this.onTap, this.photo, this.selected = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: selected ? AppColors.gold : AppColors.card,
        borderRadius: BorderRadius.circular(24),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: EdgeInsets.fromLTRB(photo == null ? 22 : 5, 5, photo == null ? 22 : 16, 5),
            child: Row(children: [
              if (photo != null) ...[
                ClipOval(child: Image.asset(photo!, width: 34, height: 34, fit: BoxFit.cover, cacheWidth: 102)),
                const SizedBox(width: 8),
              ],
              Text(label,
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? const Color(0xFF17130E) : AppColors.textPrimary)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Round white button in the header (notifications, admin), with a red dot.
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
        color: AppColors.card,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Stack(alignment: Alignment.center, children: [
              Icon(icon, size: 22, color: AppColors.textPrimary),
              if (badge > 0)
                Positioned(
                  right: 12,
                  top: 11,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE5484D),
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.card, width: 1.5),
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

/// The black banner near the top of Home, photo in an arch on the right.
class _RequestCard extends StatelessWidget {
  final VoidCallback onTap;
  const _RequestCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.isDark ? const Color(0xFF1E1912) : const Color(0xFF141210),
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 170,
          child: Stack(children: [
            Positioned(
              right: -4,
              bottom: 0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(80)),
                child: Image.asset('assets/photos/offer_default.jpg', width: 150, height: 176, fit: BoxFit.cover, cacheWidth: 450),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 160, 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('CAN\'T FIND YOUR STYLE?',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: AppColors.gold)),
                const SizedBox(height: 6),
                const Text('Post a request, pros send their price',
                    maxLines: 3,
                    style: TextStyle(
                        fontFamily: 'InterDisplay',
                        fontSize: 21,
                        height: 1.12,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                        color: Color(0xFFF7F3EC))),
                const Spacer(),
                Container(
                  height: 34,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(color: const Color(0xFFF7F3EC), borderRadius: BorderRadius.circular(20)),
                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Post a request', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF17130E))),
                    SizedBox(width: 6),
                    Icon(TablerIcons.arrow_right, size: 16, color: Color(0xFF17130E)),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
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

/// A pro on Home: their work photo, rating on the photo, a heart to save.
class _StylistCard extends StatelessWidget {
  final Map<String, dynamic> provider;
  final String? photo;
  final bool saved;
  final VoidCallback onSave;
  const _StylistCard({required this.provider, required this.photo, required this.saved, required this.onSave});

  @override
  Widget build(BuildContext context) {
    final name = (provider['profiles']?['full_name'] ?? 'Beauty pro').toString();
    final area = (provider['area'] ?? provider['profiles']?['location'] ?? '').toString();
    final rating = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final featured = DateTime.tryParse((provider['featured_until'] ?? '').toString())?.isAfter(DateTime.now()) ?? false;
    return SizedBox(
      width: 196,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(24),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/provider/${provider['provider_id']}'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 158,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  ProPhoto(name: name, url: photo, radius: 18),
                  Positioned(top: 8, right: 8, child: HeartButton(saved: saved, onTap: onSave)),
                  Positioned(
                    left: 8,
                    bottom: 8,
                    child: PhotoBadge(text: reviews > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New'),
                  ),
                  if (featured) const Positioned(right: 8, bottom: 8, child: PhotoBadge(text: 'Featured', gold: true)),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 10, 6, 0),
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(6, 2, 6, 0),
                child: Row(children: [
                  if (provider['profiles']?['is_verified'] == true || provider['is_verified'] == true) ...[
                    Icon(TablerIcons.rosette_discount_check_filled, size: 14, color: AppColors.info),
                    const SizedBox(width: 3),
                  ],
                  Expanded(
                    child: Text(area.isEmpty ? 'Zimbabwe' : area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ),
                ]),
              ),
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
      (TablerIcons.search, 'Find a beauty pro', 'Browse verified pros, prices and real reviews.'),
      (TablerIcons.calendar_check, 'Book a time', 'Pick a slot that suits you, then pay the pro directly.'),
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
