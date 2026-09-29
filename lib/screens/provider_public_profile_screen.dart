import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../services/guest_service.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart' show shareOnWhatsApp;

class ProviderPublicProfileScreen extends StatefulWidget {
  final String providerId;
  const ProviderPublicProfileScreen({super.key, required this.providerId});
  @override
  State<ProviderPublicProfileScreen> createState() =>
      _ProviderPublicProfileScreenState();
}

class _ProviderPublicProfileScreenState
    extends State<ProviderPublicProfileScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _providerProfile;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _gallery = [];
  bool _loading = true;
  String? _error;
  bool _isFavorited = false;
  Map<String, dynamic>? _loyalty;
  List<Map<String, dynamic>> _certificates = [];
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic>? _salon;

  late final AnimationController _heartController;
  late final Animation<double> _heartScale;

  bool get _isLoggedIn => supabase.auth.currentUser != null;

  @override
  void initState() {
    super.initState();
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _heartScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 50),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 50),
    ]).animate(CurvedAnimation(parent: _heartController, curve: Curves.easeInOut));
    _load();
  }

  @override
  void dispose() {
    _heartController.dispose();
    super.dispose();
  }

  void _promptSignIn({String action = 'continue'}) {
    showModalBottomSheet(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => SheetScroll(child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderStrong,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(TablerIcons.lock,
                  color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Sign in to $action',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a free account or sign in to book appointments, save favorites, and more.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/register');
                },
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                ),
                child: const Text('Create Account',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  Navigator.pop(context);
                  context.go('/login');
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                ),
                child: const Text('Sign In',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                if (await GuestService.continueAsGuest(context) && mounted) {
                  setState(() {});
                  if (_services.isNotEmpty && action.contains('book')) {
                    context.push('/book/${widget.providerId}/${_services.first['id']}');
                  }
                }
              },
              child: const Text('Continue as guest'),
            ),
          ],
        ),
      )),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final id = widget.providerId;

      final profileResponse = await supabase
          .from('profiles')
          .select()
          .eq('id', id)
          .maybeSingle();

      if (profileResponse == null) {
        setState(() {
          _error = 'Provider not found';
          _loading = false;
        });
        return;
      }
      _profile = profileResponse;

      try {
        final ppResponse = await supabase
            .from('provider_profiles')
            .select()
            .eq('provider_id', id)
            .maybeSingle();
        _providerProfile = ppResponse;
      } catch (e) {
        _providerProfile = null;
      }

      try {
        final servicesResponse = await supabase
            .from('services')
            .select('*, service_categories(name, studio_only, min_age, patch_test), service_tiers(name, price, duration_minutes, is_active, sort_order)')
            .eq('provider_id', id)
            .eq('is_active', true)
            .order('created_at');
        _services = List<Map<String, dynamic>>.from(servicesResponse);
      } catch (e) {
        _services = [];
      }


      try {
        _products = List<Map<String, dynamic>>.from(await supabase
            .from('products')
            .select('id, name, price, description, image_url')
            .eq('provider_id', id)
            .eq('is_active', true)
            .order('created_at', ascending: false));
      } catch (_) {}

      try {
        final m = await supabase
            .from('salon_members')
            .select('salons(id, name)')
            .eq('provider_id', id)
            .maybeSingle();
        _salon = (m?['salons'] as Map?)?.cast<String, dynamic>();
      } catch (_) {}

      try {
        _certificates = List<Map<String, dynamic>>.from(await supabase
            .from('provider_certificates')
            .select('title, issuer, year')
            .eq('provider_id', id)
            .order('created_at'));
      } catch (_) {}

      try {
        final galleryResponse = await supabase
            .from('hairstyle_gallery')
            .select('*, service_categories(name)')
            .eq('provider_id', id)
            .eq('is_approved', true)
            .order('uploaded_at', ascending: false);
        _gallery = List<Map<String, dynamic>>.from(galleryResponse);
      } catch (e) {
        _gallery = [];
      }

      final currentUser = supabase.auth.currentUser;
      if (currentUser != null) {
        final fav = await supabase
            .from('favorites')
            .select()
            .eq('client_id', currentUser.id)
            .eq('provider_id', id)
            .maybeSingle();
        _isFavorited = fav != null;
        if (((_providerProfile?['loyalty_visits'] as num?) ?? 0) > 0 && currentUser.id != id) {
          try {
            _loyalty = Map<String, dynamic>.from(
                await supabase.rpc('loyalty_status', params: {'p_provider': id}) as Map);
          } catch (_) {}
        }
      }

      if (mounted) {
        setState(() => _loading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load profile';
          _loading = false;
        });
      }
    }
  }

  Future<void> _toggleFavorite() async {
    if (!_isLoggedIn) {
      _promptSignIn(action: 'save favorites');
      return;
    }

    final currentUser = supabase.auth.currentUser!;
    try {
      if (_isFavorited) {
        await supabase
            .from('favorites')
            .delete()
            .eq('client_id', currentUser.id)
            .eq('provider_id', widget.providerId);
        setState(() => _isFavorited = false);
      } else {
        await supabase.from('favorites').insert({
          'client_id': currentUser.id,
          'provider_id': widget.providerId,
        });
        setState(() => _isFavorited = true);
        _heartController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _openGalleryViewer(int initialIndex) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _GalleryViewerScreen(
          images: _gallery,
          initialIndex: initialIndex,
        ),
      ),
    );
  }

  void _showServicePicker(BuildContext context) {
    if (!_isLoggedIn) {
      _promptSignIn(action: 'book an appointment');
      return;
    }

    showModalBottomSheet(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      builder: (_) => SheetScroll(child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xxl, AppSpacing.sm, AppSpacing.xxl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Select a Service', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.lg),
            ..._services.map((s) {
              final cat = s['service_categories'] as Map?;
              return Container(
                margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                decoration: BoxDecoration(
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: AppColors.border),
                ),
                child: ListTile(
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Center(
                      child: Icon(categoryIcon(cat?['name']), size: 20, color: AppColors.primary),
                    ),
                  ),
                  title: Text(s['service_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${s['duration_minutes']} min',
                    style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  ),
                  trailing: Text(
                    _priceLabel(s),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: AppColors.primary,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/book/${widget.providerId}/${s['id']}');
                  },
                ),
              );
            }),
          ],
        ),
      )),
    );
  }

  void _showProduct(Map<String, dynamic> p) {
    final phone = (_profile?['whatsapp_number'] ?? _profile?['phone'] ?? '').toString();
    final name = (_profile?['full_name'] ?? 'the pro').toString();
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SheetScroll(child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if ((p['image_url'] ?? '').toString().isNotEmpty) ...[
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network(p['image_url'], height: 220, fit: BoxFit.cover),
              ),
              const SizedBox(height: 14),
            ],
            Text(p['name'] ?? '', style: Theme.of(ctx).textTheme.headlineSmall),
            if (p['price'] != null)
              Text('\$${(p['price'] as num).toStringAsFixed((p['price'] as num) % 1 == 0 ? 0 : 2)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
            if ((p['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(p['description'], style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
            ],
            const SizedBox(height: 16),
            if (phone.isNotEmpty)
              FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366)),
                onPressed: () => shareOnWhatsApp(
                    'Hi $name, I saw your ${p['name']} on BeauTap. Is it available?',
                    phone: phone),
                icon: const Icon(TablerIcons.brand_whatsapp),
                label: const Text('Ask on WhatsApp'),
              )
            else
              Text('Ask the pro about it when you book.', style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            Text('BeauTap only shows the ad. You pay the pro directly.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ]),
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: const LoadingPlaceholder(kind: PlaceholderKind.profile),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Provider Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(TablerIcons.alert_circle, size: 64, color: AppColors.error),
              const SizedBox(height: AppSpacing.lg),
              Text(_error!, style: TextStyle(color: AppColors.error)),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                onPressed: () => _load(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_profile == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Provider Profile')),
        body: const Center(child: Text('Provider not found')),
      );
    }

    final name = _profile?['full_name'] ?? 'Provider';
    final status = _providerProfile?['availability_status'] ?? 'offline';
    final bio = _providerProfile?['bio'] ?? '';
    final address = _providerProfile?['address'] ?? '';

    Color statusColor;
    switch (status) {
      case 'available':
        statusColor = AppColors.available;
        break;
      case 'busy':
        statusColor = AppColors.busy;
        break;
      default:
        statusColor = AppColors.offline;
    }

    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = (_providerProfile?['total_reviews'] as num?)?.toInt() ?? 0;
    final idVerified = _profile?['is_verified'] == true;
    final bizVerified = _profile?['is_business_verified'] == true;
    final location = address.isNotEmpty ? address : (_profile?['location'] ?? '').toString();
    final isSelf = _isLoggedIn && supabase.auth.currentUser!.id == widget.providerId;

    final title = (_providerProfile?['title'] ?? '').toString();
    final subtitle = [
      if (title.isNotEmpty) title,
      status == 'available' ? 'Available today' : status == 'busy' ? 'Busy right now' : 'Offline',
    ].join(' · ');

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: ForestHeader(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      if (Navigator.of(context).canPop())
                        IconButton(
                          icon: const Icon(TablerIcons.arrow_left, color: Colors.white),
                          tooltip: 'Back',
                          onPressed: () => Navigator.of(context).pop(),
                        )
                      else
                        const SizedBox(width: 48),
                      const Spacer(),
                      if (_providerProfile?['slug'] != null)
                        IconButton(
                          icon: const Icon(TablerIcons.share_2, color: Colors.white),
                          tooltip: 'Share',
                          onPressed: () => _share(name),
                        ),
                      if (!isSelf)
                        ScaleTransition(
                          scale: _heartScale,
                          child: IconButton(
                            icon: Icon(
                              _isFavorited ? TablerIcons.heart_filled : TablerIcons.heart,
                              color: _isFavorited ? AppColors.gold : Colors.white,
                            ),
                            tooltip: _isFavorited ? 'Remove from favourites' : 'Save to favourites',
                            onPressed: _toggleFavorite,
                          ),
                        ),
                    ]),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                      child: Row(children: [
                        Stack(children: [
                          Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                            child: Container(
                              decoration: const BoxDecoration(color: AppColors.pine, shape: BoxShape.circle),
                              child: _profile?['avatar_url'] != null
                                  ? PersonAvatar(name: name, url: _profile?['avatar_url'], size: 76)
                                  : SizedBox(
                                      width: 76,
                                      height: 76,
                                      child: Center(
                                        child: Text(
                                          name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                                        ),
                                      ),
                                    ),
                            ),
                          ),
                          Positioned(
                            right: 2,
                            bottom: 4,
                            child: Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                                border: Border.all(color: AppColors.primary, width: 2.5),
                              ),
                            ),
                          ),
                        ]),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, letterSpacing: -0.24)),
                            const SizedBox(height: 2),
                            Text(subtitle, style: const TextStyle(color: Color(0xFFD5E2DC), fontSize: 15)),
                          ]),
                        ),
                      ]),
                    ),
                    if (idVerified || bizVerified || _providerProfile?['gender'] != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 14, 12, 0),
                        child: Wrap(spacing: 6, runSpacing: 6, children: [
                          if (idVerified) const _DarkBadge(icon: TablerIcons.id_badge_2, label: 'ID verified'),
                          if (bizVerified) const _DarkBadge(icon: TablerIcons.building_store, label: 'Business verified'),
                          if (_providerProfile?['gender'] != null)
                            _DarkBadge(
                                icon: TablerIcons.user,
                                label: _providerProfile!['gender'] == 'woman' ? 'Woman' : 'Man'),
                        ]),
                      ),
                  ]),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(children: [
                    IntrinsicHeight(
                      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: _InfoTile(
                            onTap: total == 0 ? null : () => context.push('/provider/${widget.providerId}/reviews'),
                            top: Row(children: [
                              const Icon(TablerIcons.star_filled, size: 20, color: Color(0xFFA8822F)),
                              const SizedBox(width: 4),
                              Text(total == 0 ? 'New' : avg.toStringAsFixed(1),
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                            ]),
                            bottom: total == 0 ? 'No reviews yet' : '$total ${total == 1 ? 'review' : 'reviews'}',
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Builder(builder: (_) {
                            final modes = _services.map((sv) => sv['location_mode'] ?? 'client').toSet();
                            final comes = modes.contains('client') || modes.contains('either');
                            final studio = modes.contains('studio') || modes.contains('either');
                            final area = location.isEmpty ? 'Zimbabwe' : location;
                            return _InfoTile(
                              top: Text(
                                  comes ? 'Comes to you' : 'At their place',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                              bottom: comes && studio ? 'or go to them, $area' : area,
                            );
                          }),
                        ),
                      ]),
                    ),
                    if (_loyalty?['enabled'] == true) ...[
                      const SizedBox(height: 16),
                      _LoyaltyCard(status: _loyalty!),
                    ],
                  ]),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isLoggedIn) ...[
                    SoftBanner(
                      icon: TablerIcons.user,
                      color: AppColors.primary,
                      title: 'Sign in to book',
                      message: 'Create a free account to book, save favourites and chat.',
                      actionLabel: 'Sign in',
                      onTap: () => context.go('/login'),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Bio
                  if (bio.isNotEmpty) ...[
                    Text('About', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      bio,
                      style: TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],

                  if (_salon != null) ...[
                    InkWell(
                      onTap: () => context.push('/salon/${_salon!['id']}'),
                      borderRadius: AppRadius.mdAll,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppRadius.mdAll,
                        ),
                        child: Row(children: [
                          Icon(TablerIcons.building_store, color: AppColors.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text.rich(TextSpan(children: [
                              const TextSpan(text: 'Works at '),
                              TextSpan(text: _salon!['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                            ])),
                          ),
                          Text('See team', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                          Icon(TablerIcons.chevron_right, color: AppColors.primary, size: 18),
                        ]),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  if (_certificates.isNotEmpty) ...[
                    Text('Qualifications', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: AppSpacing.sm),
                    for (final c in _certificates)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(children: [
                          Icon(TablerIcons.certificate, size: 18, color: AppColors.primary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              [c['title'], c['issuer'], c['year']].where((x) => x != null).join(' · '),
                              style: const TextStyle(fontSize: 14),
                            ),
                          ),
                        ]),
                      ),
                    const SizedBox(height: AppSpacing.xl),
                  ],

                  // Services
                  Text('Services', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.md),
                  if (_services.isEmpty)
                    Text('No services listed yet.', style: TextStyle(color: AppColors.textSecondary))
                  else
                    Container(
                      decoration: BoxDecoration(
                        color: AppColors.card,
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(color: AppColors.border),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(children: [
                        for (var k = 0; k < _services.length; k++) ...[
                          if (k > 0) const Divider(height: 1),
                          Builder(builder: (context) {
                            final sv = _services[k];
                            final tiers = (sv['service_tiers'] as List? ?? []).where((t) => t['is_active'] == true).length;
                            final mins = (sv['duration_minutes'] as num?)?.toInt() ?? 60;
                            final dur = mins >= 60
                                ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60} min' : ''}'
                                : '$mins min';
                            return InkWell(
                              onTap: () => _showServiceDetails(sv),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                                child: Row(children: [
                                  if (sv['image_url'] != null) ...[
                                    ClipRRect(
                                      borderRadius: AppRadius.smAll,
                                      child: Image.network(sv['image_url'], width: 44, height: 44, fit: BoxFit.cover,
                                          errorBuilder: (_, _, _) => const SizedBox(width: 44, height: 44)),
                                    ),
                                    const SizedBox(width: 12),
                                  ],
                                  Expanded(
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text(sv['service_name'] ?? '',
                                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                                      const SizedBox(height: 2),
                                      Text('$dur${tiers > 0 ? ' · $tiers options' : ''}',
                                          style: Theme.of(context).textTheme.bodySmall),
                                    ]),
                                  ),
                                  Text(_priceLabel(sv),
                                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
                                ]),
                              ),
                            );
                          }),
                        ],
                      ]),
                    ),

                  const SizedBox(height: AppSpacing.xxl),

                  if (_products.isNotEmpty) ...[
                    Text('Products', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Text('Sold by this pro. Ask them on WhatsApp to buy.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 196,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _products.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 10),
                        itemBuilder: (_, i) => _ProductCard(
                          product: _products[i],
                          onTap: () => _showProduct(_products[i]),
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],

                  // Gallery
                  Text('Gallery', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  if (_gallery.isEmpty)
                    Text(
                      'No gallery photos yet.',
                      style: TextStyle(color: AppColors.textTertiary),
                    )
                  else
                    GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: _gallery.length,
                      itemBuilder: (_, i) {
                        final img = _gallery[i];
                        return GestureDetector(
                          onTap: () => _openGalleryViewer(i),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Image.network(
                              img['image_url'],
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.surfaceLight,
                                child: Icon(TablerIcons.photo_off, color: AppColors.textTertiary),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                  const SizedBox(height: 100),
                ],
              ),
            ),
              ),
            ),
          ),
        ],
      ),

      bottomNavigationBar: _buildBottomBar(context, status),
    );
  }

  void _book(Map<String, dynamic> s) {
    if (!_isLoggedIn) {
      _promptSignIn(action: 'book an appointment');
    } else {
      context.push('/book/${widget.providerId}/${s['id']}');
    }
  }

  void _share(String name) {
    final link = 'https://beautyapp-swart.vercel.app/@${_providerProfile!['slug']}';
    showModalBottomSheet(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      builder: (ctx) => SheetScroll(child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Share $name', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(link, style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Book $name on BeauTap: $link')}'),
                  mode: LaunchMode.externalApplication);
            },
            icon: const Icon(TablerIcons.message_circle, size: 18),
            label: const Text('Share on WhatsApp'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: link));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
              }
            },
            icon: const Icon(TablerIcons.copy, size: 18),
            label: const Text('Copy link'),
          ),
        ]),
      )),
    );
  }

  void _showServiceDetails(Map<String, dynamic> s) {
    final tiers = (s['service_tiers'] as List? ?? []).where((t) => t['is_active'] == true).toList()
      ..sort((a, b) => ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0) as num));
    final includes = (s['includes'] as String? ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final desc = (s['description'] as String? ?? '').trim();
    final aftercare = (s['aftercare'] as String? ?? '').trim();
    String money(num v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: s['image_url'] != null ? 0.85 : 0.6,
        maxChildSize: 0.95,
        builder: (ctx, scroll) => Column(children: [
          Expanded(
            child: ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(20, 0, 20, 16), children: [
              if (s['image_url'] != null) ...[
                ClipRRect(
                  borderRadius: AppRadius.lgAll,
                  child: AspectRatio(
                    aspectRatio: 4 / 3,
                    child: Image.network(s['image_url'], fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(color: AppColors.surfaceMuted)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              Text(s['service_name'] ?? '', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('${_priceLabel(s)} · ${s['duration_minutes']} min',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill(
                  label: switch (s['location_mode']) {
                    'studio' => 'At their place',
                    'either' => 'Your place or theirs',
                    _ => 'Comes to you',
                  },
                  icon: s['location_mode'] == 'studio' ? TablerIcons.building_store : TablerIcons.home,
                ),
                if (s['patch_test'] == true)
                  Pill(label: 'Patch test first', icon: TablerIcons.alert_circle, color: AppColors.warningText),
                if (s['service_categories']?['min_age'] != null)
                  Pill(label: '${s['service_categories']['min_age']}+ only', color: AppColors.errorText),
              ]),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(desc, style: TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary)),
              ],
              if (tiers.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('Options', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final t in tiers)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text('${t['name']}', style: const TextStyle(fontSize: 14.5))),
                      Text('${t['duration_minutes']} min  ',
                          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                      Text(money(t['price'] as num), style: const TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                  ),
              ],
              if (includes.isNotEmpty) ...[
                const SizedBox(height: 20),
                Text('What\'s included', style: Theme.of(ctx).textTheme.titleSmall),
                const SizedBox(height: 8),
                for (final l in includes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(TablerIcons.circle_check_filled, size: 18, color: AppColors.success),
                      const SizedBox(width: 8),
                      Expanded(child: Text(l, style: const TextStyle(fontSize: 14.5))),
                    ]),
                  ),
              ],
              if (aftercare.isNotEmpty) ...[
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(TablerIcons.leaf, size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Aftercare', style: TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 6),
                    Text(aftercare, style: TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary)),
                  ]),
                ),
              ],
            ]),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20, 8, 20, 16 + MediaQuery.of(ctx).padding.bottom),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _book(s);
                },
                child: const Text('Book this'),
              ),
            ),
          ),
        ]),
      ),
    );
  }

  String _priceLabel(Map<String, dynamic> s) {
    final tiers = (s['service_tiers'] as List? ?? []).where((t) => t['is_active'] == true).toList();
    if (tiers.isEmpty) return '\$${s['price']}';
    final min = tiers.map((t) => (t['price'] as num).toDouble()).reduce((a, b) => a < b ? a : b);
    return 'from \$${min.toStringAsFixed(min % 1 == 0 ? 0 : 2)}';
  }

  Widget _buildBottomBar(BuildContext context, String status) {
    num? minPrice;
    for (final sv in _services) {
      final tiers = (sv['service_tiers'] as List? ?? []).where((t) => t['is_active'] == true);
      for (final p in [sv['price'], ...tiers.map((t) => t['price'])]) {
        if (p is num && (minPrice == null || p < minPrice)) minPrice = p;
      }
    }
    final hasLocation = _providerProfile?['city_id'] != null && (_providerProfile?['area'] ?? '').toString().trim().isNotEmpty;
    final canBook = status != 'offline' && _services.isNotEmpty && hasLocation;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: AppColors.card,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (minPrice != null) ...[
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('From', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            Text('\$${minPrice.toStringAsFixed(minPrice % 1 == 0 ? 0 : 2)}',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: FilledButton(
            onPressed: canBook ? () => _showServicePicker(context) : null,
            child: Text(!canBook
                ? (_services.isEmpty
                    ? 'No services yet'
                    : !hasLocation
                        ? 'Not taking bookings yet'
                        : 'Not taking bookings right now')
                : _isLoggedIn
                    ? 'Book'
                    : 'Sign in to book'),
          ),
        ),
      ]),
    );
  }
}

class _GalleryViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  const _GalleryViewerScreen({required this.images, required this.initialIndex});
  @override
  State<_GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<_GalleryViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.images[_currentIndex];
    final category = (img['service_categories'] as Map?)?['name'] ?? '';
    final caption = img['caption'] as String? ?? '';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          '${_currentIndex + 1} / ${widget.images.length}',
          style: const TextStyle(fontSize: 16),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: widget.images.length,
              onPageChanged: (i) => setState(() => _currentIndex = i),
              itemBuilder: (_, i) {
                return InteractiveViewer(
                  minScale: 0.5,
                  maxScale: 3.0,
                  child: Center(
                    child: Image.network(
                      widget.images[i]['image_url'],
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        TablerIcons.photo_off,
                        color: Colors.white38,
                        size: 64,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          if (caption.isNotEmpty || category.isNotEmpty)
            Container(
              width: double.infinity,
              padding: EdgeInsets.only(
                left: AppSpacing.xl,
                right: AppSpacing.xl,
                top: AppSpacing.md,
                bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
              ),
              color: Colors.black,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (category.isNotEmpty)
                    Text(
                      category,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.5),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (caption.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      caption,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _InfoTile extends StatelessWidget {
  final Widget top;
  final String bottom;
  final VoidCallback? onTap;
  const _InfoTile({required this.top, required this.bottom, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.border)),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            top,
            const SizedBox(height: 4),
            Text(bottom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// Verified badge on the dark header: gold text on 18% gold.
class _DarkBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  const _DarkBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: AppColors.gold.withValues(alpha: 0.18), borderRadius: AppRadius.xsAll),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 15, color: AppColors.goldLight),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AppColors.goldLight)),
      ]),
    );
  }
}

class _LoyaltyCard extends StatelessWidget {
  final Map<String, dynamic> status;
  const _LoyaltyCard({required this.status});

  @override
  Widget build(BuildContext context) {
    final needed = (status['visits_needed'] as num).toInt();
    final progress = (status['progress'] as num).toInt();
    final pct = (status['percent'] as num).toInt();
    final available = status['available'] == true;
    final stamps = needed - 1;
    final done = available ? stamps : progress;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: AppColors.cream, borderRadius: AppRadius.mdAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(
            child: Text('Loyalty card', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
          ),
          Text(available ? 'Next booking $pct% off' : '$done of $needed · $pct% off',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.goldText)),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (var i = 0; i < stamps; i++)
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: i < done ? AppColors.primary : Colors.transparent,
                borderRadius: AppRadius.smAll,
                border: i < done ? null : Border.all(color: AppColors.gold, width: 1.2),
              ),
              child: i < done ? const Icon(TablerIcons.check, size: 18, color: AppColors.goldLight) : null,
            ),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: AppColors.gold, borderRadius: AppRadius.smAll),
            child: Icon(TablerIcons.gift, size: 20, color: AppColors.textPrimary),
          ),
        ]),
        if (!available) ...[
          const SizedBox(height: 10),
          Text('${stamps - progress} more ${stamps - progress == 1 ? 'visit' : 'visits'} to your reward. Applied automatically.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}

class _ProductCard extends StatelessWidget {
  final Map<String, dynamic> product;
  final VoidCallback onTap;
  const _ProductCard({required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final img = (product['image_url'] ?? '').toString();
    final price = product['price'] as num?;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        width: 140,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 120,
            width: double.infinity,
            child: img.isEmpty
                ? Container(color: AppColors.primarySoft, child: Icon(TablerIcons.shopping_bag, color: AppColors.primary))
                : Image.network(img, fit: BoxFit.cover),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(product['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              if (price != null)
                Text('\$${price.toStringAsFixed(price % 1 == 0 ? 0 : 2)}',
                    style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
            ]),
          ),
        ]),
      ),
    );
  }
}
