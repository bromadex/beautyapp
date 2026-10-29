import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/specialties.dart';
import '../services/guest_service.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart' show shareOnWhatsApp;
import '../utils/nav.dart';
import '../utils/feel.dart';

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
  /// Add-ons (extras) per service id.
  Map<String, List<Map<String, dynamic>>> _addons = {};
  Map<String, dynamic>? _topReview;
  int _completed = 0;
  int _tab = 0; // Services, Work, Reviews, About
  bool _scrolled = false; // photo scrolled away: show the solid top bar
  String? _openService;
  final Map<String, String> _pickedTier = {};
  final Map<String, Set<String>> _pickedAddons = {};

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
            .select('*, cities(name)')
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
        final rows = await supabase
            .from('service_addons')
            .select('id, service_id, name, price, duration_minutes, sort_order')
            .eq('provider_id', id)
            .eq('is_active', true)
            .order('sort_order');
        _addons = {};
        for (final r in rows) {
          (_addons[r['service_id'] as String] ??= []).add(Map<String, dynamic>.from(r));
        }
      } catch (_) {}

      try {
        final r = await supabase
            .from('reviews')
            .select('rating, comment, created_at, client:profiles!reviews_client_id_fkey(full_name, avatar_url)')
            .eq('provider_id', id)
            .gte('rating', 5)
            .neq('comment', '')
            .order('created_at', ascending: false)
            .limit(1);
        _topReview = r.isEmpty ? null : Map<String, dynamic>.from(r.first);
      } catch (_) {}

      try {
        _completed = ((await supabase.rpc('provider_completed_bookings', params: {'p_provider': id})) as num?)?.toInt() ?? 0;
      } catch (_) {}

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
          proName: (_profile?['full_name'] ?? 'this pro').toString(),
          onBook: _services.isEmpty
              ? null
              : (img) {
                  Navigator.of(context).pop();
                  // The service in the same category as the photo, if there is one.
                  final match = _services.where((sv) => sv['category_id'] == img['category_id']).firstOrNull;
                  match != null ? _bookPicked(match) : _showServicePicker(context);
                },
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

    final name = (_profile?['full_name'] ?? 'Provider').toString();
    final status = _providerProfile?['availability_status'] ?? 'offline';
    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = (_providerProfile?['total_reviews'] as num?)?.toInt() ?? 0;
    final isSelf = _isLoggedIn && supabase.auth.currentUser!.id == widget.providerId;
    final title = (_providerProfile?['title'] ?? '').toString();
    // Area and city only. The street address is private until a booking is confirmed.
    final area = (_providerProfile?['area'] ?? '').toString();
    final city = ((_providerProfile?['cities'] as Map?)?['name'] ?? '').toString();
    final place = [area, city].where((x) => x.isNotEmpty).join(', ');
    final locationText = place.isNotEmpty ? place : (_profile?['location'] ?? '').toString();
    final cover = _gallery.isNotEmpty ? _gallery.first['image_url'] as String? : _profile?['avatar_url'] as String?;

    return Scaffold(
      bottomNavigationBar: _buildBottomBar(context, status),
      body: Stack(children: [
        NotificationListener<ScrollNotification>(
          onNotification: (n) {
            final past = n.metrics.pixels > 220;
            if (n.depth == 0 && past != _scrolled) setState(() => _scrolled = past);
            return false;
          },
          child: CustomScrollView(slivers: [
          SliverToBoxAdapter(
            child: Stack(children: [
              // Big work photo; the profile sheet overlaps its bottom edge.
              SizedBox(
                height: 300,
                width: double.infinity,
                child: GestureDetector(
                  onTap: _gallery.isEmpty ? null : () => _openGalleryViewer(0),
                  child: ProPhoto(name: name, url: cover, radius: 0),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 268),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
                  child: _identity(name, title, locationText, status, avg, total),
                ),
              ),
            ]),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _actions(name, locationText),
                _stats(),
                if (_loyalty?['enabled'] == true) ...[const SizedBox(height: 12), _LoyaltyCard(status: _loyalty!)],
                if (!_isLoggedIn) ...[
                  const SizedBox(height: 14),
                  SoftBanner(
                    icon: TablerIcons.user,
                    color: AppColors.goldText,
                    title: 'Sign in to book',
                    message: 'Create a free account to book, save favourites and chat.',
                    actionLabel: 'Sign in',
                    onTap: () => context.go('/login'),
                  ),
                ],
                const SizedBox(height: 18),
                _tabs(total),
                const SizedBox(height: 14),
                AnimatedSwitcher(
                  duration: Motion.of(context, Motion.fast),
                  child: KeyedSubtree(
                    key: ValueKey(_tab),
                    child: switch (_tab) {
                      0 => _servicesTab(),
                      1 => _workTab(),
                      2 => _reviewsTab(total),
                      _ => _aboutTab(),
                    },
                  ),
                ),
              ]),
            ),
          ),
        ])),
        // Buttons float over the photo; once it scrolls away a solid bar
        // with the pro's name fades in behind them.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: AnimatedContainer(
            duration: Motion.of(context, Motion.fast),
            decoration: BoxDecoration(
              color: _scrolled ? AppColors.surfaceLight : Colors.transparent,
              border: Border(bottom: BorderSide(color: _scrolled ? AppColors.border : Colors.transparent)),
            ),
            child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(children: [
                _RoundButton(icon: TablerIcons.chevron_left, tooltip: 'Back', onTap: () => goBack(context)),
                Expanded(
                  child: AnimatedOpacity(
                    duration: Motion.of(context, Motion.fast),
                    opacity: _scrolled ? 1 : 0,
                    child: Text(name,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                ),
                _RoundButton(icon: TablerIcons.share_2, tooltip: 'Share', onTap: () => _share(name)),
                if (!isSelf) ...[
                  const SizedBox(width: 10),
                  ScaleTransition(
                    scale: _heartScale,
                    child: _RoundButton(
                      icon: _isFavorited ? TablerIcons.heart_filled : TablerIcons.heart,
                      color: _isFavorited ? const Color(0xFFE5484D) : null,
                      tooltip: _isFavorited ? 'Remove from saved' : 'Save',
                      onTap: () {
                        Haptics.firm();
                        _toggleFavorite();
                      },
                    ),
                  ),
                ],
              ]),
            ),
          ),
          ),
        ),
      ]),
    );
  }

  Widget _identity(String name, String title, String place, String status, double avg, int total) {
    final idVerified = _profile?['is_verified'] == true;
    final bizVerified = _profile?['is_business_verified'] == true;
    final modes = _services.map((sv) => sv['location_mode'] ?? 'client').toSet();
    final comes = modes.contains('client') || modes.contains('either');
    final studio = modes.contains('studio') || modes.contains('either');
    final deposit = (_providerProfile?['deposit_percent'] as num?)?.toInt() ?? 0;
    final kindText = title.isNotEmpty ? title : '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Portrait overlapping the photo.
        Transform.translate(
          offset: const Offset(0, -46),
          child: Container(
            width: 104,
            height: 124,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: AppColors.surfaceLight, width: 4),
              boxShadow: const [BoxShadow(color: Color(0x2E000000), blurRadius: 20, offset: Offset(0, 8))],
            ),
            child: ProPhoto(name: name, url: _profile?['avatar_url'] as String?, radius: 22),
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'InterDisplay',
                          fontSize: 23,
                          height: 1.1,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: AppColors.textPrimary)),
                ),
                if (idVerified || bizVerified) ...[
                  const SizedBox(width: 5),
                  Icon(TablerIcons.rosette_discount_check_filled, size: 19, color: AppColors.info),
                ],
              ]),
              const SizedBox(height: 4),
              Text([if (kindText.isNotEmpty) kindText, if (place.isNotEmpty) place].join(' · '),
                  maxLines: 2, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(height: 5),
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
                Text(total == 0 ? 'New on BeauTap' : '★ ${avg.toStringAsFixed(1)}',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                if (total > 0)
                  Text('($total ${total == 1 ? 'review' : 'reviews'})',
                      style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Text(
                  status == 'available' ? '● Available' : status == 'busy' ? '● Busy now' : '● Offline',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: status == 'available' ? AppColors.success : status == 'busy' ? AppColors.warningText : AppColors.textTertiary),
                ),
              ]),
            ]),
          ),
        ),
      ]),
      Transform.translate(
        offset: const Offset(0, -30),
        child: Wrap(spacing: 6, runSpacing: 6, children: [
          if (idVerified) _Badge(icon: TablerIcons.id_badge_2, label: 'ID verified', tone: _BadgeTone.forest),
          if (bizVerified) _Badge(icon: TablerIcons.building_store, label: 'Business verified', tone: _BadgeTone.forest),
          if (comes) const _Badge(icon: TablerIcons.home, label: 'Comes to you'),
          if (studio) const _Badge(icon: TablerIcons.armchair, label: 'Studio'),
          if (deposit > 0) _Badge(icon: TablerIcons.coin, label: '$deposit% deposit', tone: _BadgeTone.gold),
          if (_providerProfile?['gender'] != null)
            _Badge(icon: TablerIcons.user, label: _providerProfile!['gender'] == 'woman' ? 'Woman' : 'Man'),
        ]),
      ),
    ]);
  }

  Widget _actions(String name, String place) {
    // Call and WhatsApp only for pros who chose to be reached that way.
    final number = (_profile?['whatsapp_number'] ?? '').toString().trim();
    final optedIn = number.isNotEmpty && ['whatsapp', 'both'].contains(_providerProfile?['preferred_contact']);
    final tiles = <Widget>[
      if (optedIn)
        _ActionTile(
          icon: TablerIcons.phone,
          label: 'Call',
          onTap: () => launchUrl(Uri.parse('tel:${number.replaceAll(' ', '')}')),
        ),
      if (optedIn)
        _ActionTile(
          icon: TablerIcons.brand_whatsapp,
          label: 'WhatsApp',
          color: const Color(0xFF25A55F),
          onTap: () => shareOnWhatsApp('Hi $name, I found you on BeauTap.', phone: number),
        ),
      if (place.isNotEmpty)
        _ActionTile(
          icon: TablerIcons.map_pin,
          label: 'Directions',
          // The pro's area, never a street address.
          onTap: () => launchUrl(
              Uri.parse('https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent('$place, Zimbabwe')}'),
              mode: LaunchMode.externalApplication),
        ),
      _ActionTile(icon: TablerIcons.share_2, label: 'Share', onTap: () => _share(name)),
    ];
    return Row(children: [
      for (var k = 0; k < tiles.length; k++) ...[if (k > 0) const SizedBox(width: 8), Expanded(child: tiles[k])],
    ]);
  }

  Widget _stats() {
    final years = (_providerProfile?['years_experience'] as num?)?.toInt();
    final since = DateTime.tryParse((_profile?['created_at'] ?? '').toString())?.year;
    final items = <(String, String)>[
      if (_completed > 0) ('$_completed', _completed == 1 ? 'booking' : 'bookings'),
      if (years != null && years > 0) ('$years ${years == 1 ? 'yr' : 'yrs'}', 'experience'),
      if (since != null) ('$since', 'on BeauTap'),
    ];
    if (items.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(vertical: 12),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20)),
      child: Row(children: [
        for (var k = 0; k < items.length; k++) ...[
          if (k > 0) Container(width: 1, height: 34, color: AppColors.border),
          Expanded(
            child: Column(children: [
              Text(items[k].$1,
                  style: TextStyle(
                      fontFamily: 'InterDisplay', fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(items[k].$2, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _tabs(int reviews) {
    const labels = ['Services', 'Work', 'Reviews', 'About'];
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        for (var k = 0; k < labels.length; k++)
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                if (_tab == k) return;
                Haptics.light();
                setState(() => _tab = k);
              },
              child: AnimatedContainer(
                duration: Motion.of(context, Motion.fast),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _tab == k ? AppColors.card : Colors.transparent,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: _tab == k ? const [BoxShadow(color: Color(0x14000000), blurRadius: 6, offset: Offset(0, 2))] : null,
                ),
                child: Text(labels[k],
                    style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: _tab == k ? AppColors.textPrimary : AppColors.textSecondary)),
              ),
            ),
          ),
      ]),
    );
  }

  List<Map<String, dynamic>> _tiersOf(Map<String, dynamic> sv) =>
      (sv['service_tiers'] as List? ?? []).where((t) => t['is_active'] == true).cast<Map<String, dynamic>>().toList()
        ..sort((a, b) => ((a['sort_order'] ?? 0) as num).compareTo((b['sort_order'] ?? 0) as num));

  /// Price of a service with the option and extras picked on this page.
  num _pickedPrice(Map<String, dynamic> sv) {
    final id = sv['id'] as String;
    final tiers = _tiersOf(sv);
    final tier = tiers.where((t) => t['id'] == _pickedTier[id]).firstOrNull ?? tiers.firstOrNull;
    num price = (tier?['price'] ?? sv['price'] ?? 0) as num;
    for (final a in _addons[id] ?? const <Map<String, dynamic>>[]) {
      if (_pickedAddons[id]?.contains(a['id']) == true) price += (a['price'] as num?) ?? 0;
    }
    return price;
  }

  String _money(num v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

  String _duration(num? m) {
    final mins = m?.toInt() ?? 60;
    return mins >= 60 ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60} min' : ''}' : '$mins min';
  }

  Widget _servicesTab() {
    if (_services.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No services listed yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final sv in _services) _serviceCard(sv),
      if (_gallery.isNotEmpty) ...[
        _sectionTitle('Recent work', _gallery.length > 3 ? 'See all ${_gallery.length}' : null, () => setState(() => _tab = 1)),
        _workStrip(),
      ],
      if (_topReview != null) ...[
        _sectionTitle('Reviews', 'All', () => context.push('/provider/${widget.providerId}/reviews')),
        _ReviewCard(review: _topReview!),
      ],
      if (_salon != null) ...[
        _sectionTitle('Works at', null, null),
        _salonCard(),
      ],
    ]);
  }

  Widget _sectionTitle(String t, String? action, VoidCallback? onAction) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 2, 10),
        child: Row(children: [
          Expanded(child: Text(t, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action, style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500, color: AppColors.goldText)),
            ),
        ]),
      );

  Widget _serviceCard(Map<String, dynamic> sv) {
    final id = sv['id'] as String;
    final tiers = _tiersOf(sv);
    final addons = _addons[id] ?? const <Map<String, dynamic>>[];
    final open = _openService == id;
    final expandable = tiers.length > 1 || addons.isNotEmpty;
    final mode = switch (sv['location_mode']) { 'studio' => 'At their place', 'either' => 'Your place or theirs', _ => 'Comes to you' };
    final sub = [
      _duration(sv['duration_minutes'] as num?),
      if (tiers.length > 1) '${tiers.length} options' else mode,
    ].join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        border: open ? Border.all(color: AppColors.gold.withValues(alpha: 0.6)) : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            if (!expandable) {
              _showServiceDetails(sv);
              return;
            }
            Haptics.light();
            setState(() => _openService = open ? null : id);
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(sv['service_name'] ?? '',
                        style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 3),
                    Text(sub, style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ]),
                ),
                Text(open ? _money(_pickedPrice(sv)) : _priceLabel(sv),
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(width: 10),
                if (!open)
                  FilledButton(
                    onPressed: () => _bookPicked(sv),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 34),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    child: const Text('Book'),
                  )
                else
                  Icon(TablerIcons.chevron_up, color: AppColors.textTertiary),
              ]),
              AnimatedSize(
                duration: Motion.of(context),
                curve: Motion.curve,
                alignment: Alignment.topCenter,
                child: !open
                    ? const SizedBox(width: double.infinity)
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        const SizedBox(height: 12),
                        Divider(height: 1, color: AppColors.border),
                        if (tiers.length > 1) ...[
                          _optLabel('Options'),
                          for (final t in tiers)
                            _OptionRow(
                              label: t['name'] ?? '',
                              detail: _duration(t['duration_minutes'] as num?),
                              price: _money(t['price'] as num),
                              selected: (_pickedTier[id] ?? tiers.first['id']) == t['id'],
                              radio: true,
                              onTap: () {
                                Haptics.light();
                                setState(() => _pickedTier[id] = t['id'] as String);
                              },
                            ),
                        ],
                        if (addons.isNotEmpty) ...[
                          _optLabel('Extras'),
                          for (final a in addons)
                            _OptionRow(
                              label: a['name'] ?? '',
                              detail: ((a['duration_minutes'] as num?) ?? 0) > 0 ? '+${_duration(a['duration_minutes'] as num)}' : null,
                              price: '+${_money((a['price'] as num?) ?? 0)}',
                              selected: _pickedAddons[id]?.contains(a['id']) == true,
                              radio: false,
                              onTap: () {
                                Haptics.light();
                                setState(() {
                                  final set = _pickedAddons[id] ??= {};
                                  set.contains(a['id']) ? set.remove(a['id']) : set.add(a['id'] as String);
                                });
                              },
                            ),
                        ],
                        const SizedBox(height: 10),
                        Row(children: [
                          TextButton(onPressed: () => _showServiceDetails(sv), child: const Text('Details')),
                          const Spacer(),
                          FilledButton(
                            onPressed: () => _bookPicked(sv),
                            style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                            child: Text('Book · ${_money(_pickedPrice(sv))}'),
                          ),
                        ]),
                      ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _optLabel(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 4),
        child: Text(t.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.textSecondary)),
      );

  /// Book a service with the option and extras picked on this page.
  void _bookPicked(Map<String, dynamic> sv) {
    if (!_isLoggedIn) {
      _promptSignIn(action: 'book an appointment');
      return;
    }
    final id = sv['id'] as String;
    final q = <String, String>{
      if (_pickedTier[id] != null) 'tier': _pickedTier[id]!,
      if ((_pickedAddons[id] ?? {}).isNotEmpty) 'addons': _pickedAddons[id]!.join(','),
    };
    final query = q.isEmpty ? '' : '?${Uri(queryParameters: q).query}';
    context.push('/book/${widget.providerId}/$id$query');
  }

  Widget _workStrip() {
    final shown = _gallery.take(3).toList();
    return Row(children: [
      for (var k = 0; k < 3; k++) ...[
        if (k > 0) const SizedBox(width: 6),
        Expanded(
          child: AspectRatio(
            aspectRatio: 3 / 4,
            child: k >= shown.length
                ? const SizedBox()
                : GestureDetector(
                    onTap: () => _openGalleryViewer(k),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Stack(fit: StackFit.expand, children: [
                        Image.network(shown[k]['image_url'], fit: BoxFit.cover, cacheWidth: 400,
                            errorBuilder: (_, _, _) => Container(color: AppColors.surfaceMuted)),
                        if (k == 2 && _gallery.length > 3)
                          Container(
                            color: const Color(0x73000000),
                            alignment: Alignment.center,
                            child: Text('+${_gallery.length - 3}',
                                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
                          ),
                      ]),
                    ),
                  ),
          ),
        ),
      ],
    ]);
  }

  Widget _workTab() {
    if (_gallery.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No photos of their work yet.', textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
      );
    }
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 3 / 4),
      itemCount: _gallery.length,
      itemBuilder: (_, i) => GestureDetector(
        onTap: () => _openGalleryViewer(i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.network(_gallery[i]['image_url'], fit: BoxFit.cover, cacheWidth: 400,
              errorBuilder: (_, _, _) => Container(
                    color: AppColors.surfaceMuted,
                    child: Icon(TablerIcons.photo_off, color: AppColors.textTertiary),
                  )),
        ),
      ),
    );
  }

  Widget _reviewsTab(int total) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (_topReview != null) _ReviewCard(review: _topReview!),
      const SizedBox(height: 12),
      if (total > 0)
        OutlinedButton.icon(
          onPressed: () => context.push('/provider/${widget.providerId}/reviews'),
          icon: const Icon(TablerIcons.star, size: 18),
          label: Text('Read all $total ${total == 1 ? 'review' : 'reviews'}'),
        )
      else
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Text('No reviews yet. Be the first to book and review.',
              textAlign: TextAlign.center, style: TextStyle(color: AppColors.textSecondary)),
        ),
    ]);
  }

  Widget _aboutTab() {
    final bio = (_providerProfile?['bio'] ?? '').toString();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (bio.isNotEmpty) ...[
        Text(bio, style: TextStyle(fontSize: 14.5, color: AppColors.textSecondary, height: 1.55)),
        const SizedBox(height: 16),
      ],
      SpecialtyChips(ids: Specialties.from(_providerProfile?['specialties'])),
      if (_certificates.isNotEmpty) ...[
        _sectionTitle('Qualifications', null, null),
        for (final c in _certificates)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(children: [
              Icon(TablerIcons.certificate, size: 18, color: AppColors.goldText),
              const SizedBox(width: 8),
              Expanded(
                child: Text([c['title'], c['issuer'], c['year']].where((x) => x != null).join(' · '),
                    style: const TextStyle(fontSize: 14)),
              ),
            ]),
          ),
      ],
      if (_salon != null) ...[_sectionTitle('Works at', null, null), _salonCard()],
      if (_products.isNotEmpty) ...[
        _sectionTitle('Products', null, null),
        Text('Sold by this pro. Ask them on WhatsApp to buy.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        SizedBox(
          height: 196,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) => _ProductCard(product: _products[i], onTap: () => _showProduct(_products[i])),
          ),
        ),
      ],
      if (bio.isEmpty && _certificates.isEmpty && _salon == null && _products.isEmpty)
        Text('This pro hasn\'t written about themselves yet.', style: TextStyle(color: AppColors.textSecondary)),
    ]);
  }

  Widget _salonCard() => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => context.push('/salon/${_salon!['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(12)),
                child: Icon(TablerIcons.building_store, color: AppColors.goldText),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(_salon!['name'] ?? '',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Text('See team', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: AppColors.goldText)),
              Icon(TablerIcons.chevron_right, size: 18, color: AppColors.goldText),
            ]),
          ),
        ),
      );

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
    final hasLocation = _providerProfile?['city_id'] != null && (_providerProfile?['area'] ?? '').toString().trim().isNotEmpty;
    final canBook = status != 'offline' && _services.isNotEmpty && hasLocation;
    final picked = _services.where((sv) => sv['id'] == _openService).firstOrNull;
    num? minPrice;
    for (final sv in _services) {
      for (final p in [sv['price'], ..._tiersOf(sv).map((t) => t['price'])]) {
        if (p is num && (minPrice == null || p < minPrice)) minPrice = p;
      }
    }
    final caption = picked != null ? (picked['service_name'] ?? '').toString() : 'from';
    final price = picked != null ? _pickedPrice(picked) : minPrice;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
      child: Row(children: [
        if (price != null) ...[
          Expanded(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
              Text(_money(price),
                  style: TextStyle(fontFamily: 'InterDisplay', fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          flex: price != null ? 0 : 1,
          child: FilledButton(
            onPressed: !canBook
                ? null
                : () => picked != null ? _bookPicked(picked) : _showServicePicker(context),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 52), padding: const EdgeInsets.symmetric(horizontal: 26)),
            child: Text(!canBook
                ? (_services.isEmpty
                    ? 'No services yet'
                    : !hasLocation
                        ? 'Not taking bookings yet'
                        : 'Not taking bookings right now')
                : _isLoggedIn
                    ? 'Book appointment'
                    : 'Sign in to book'),
          ),
        ),
      ]),
    );
  }
}

/// White circle button over the photo (back, share, save).
class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;
  const _RoundButton({required this.icon, required this.tooltip, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xEBFFFFFF),
        shape: const CircleBorder(),
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          icon: Icon(icon, color: color ?? const Color(0xFF17130E), size: 22),
          constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        ),
      );
}

enum _BadgeTone { plain, forest, gold }

class _Badge extends StatelessWidget {
  final IconData icon;
  final String label;
  final _BadgeTone tone;
  const _Badge({required this.icon, required this.label, this.tone = _BadgeTone.plain});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      _BadgeTone.forest => (AppColors.info.withValues(alpha: AppColors.isDark ? 0.16 : 0.1), AppColors.info),
      _BadgeTone.gold => (AppColors.primarySoft, AppColors.goldText),
      _BadgeTone.plain => (AppColors.surfaceMuted, AppColors.textPrimary),
    };
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(16)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: fg),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: fg)),
      ]),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  const _ActionTile({required this.icon, required this.label, required this.onTap, this.color});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: SizedBox(
            height: 68,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 22, color: color ?? AppColors.textPrimary),
              const SizedBox(height: 5),
              Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
        ),
      );
}

/// One option (radio) or extra (tick box) inside an open service card.
class _OptionRow extends StatelessWidget {
  final String label;
  final String? detail;
  final String price;
  final bool selected;
  final bool radio;
  final VoidCallback onTap;
  const _OptionRow({
    required this.label,
    required this.price,
    required this.selected,
    required this.radio,
    required this.onTap,
    this.detail,
  });

  @override
  Widget build(BuildContext context) {
    const ink = Color(0xFF17130E);
    return Semantics(
      checked: selected,
      inMutuallyExclusiveGroup: radio,
      label: '$label, $price',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.smAll,
        child: SizedBox(
          height: 42,
          child: Row(children: [
            AnimatedContainer(
              duration: Motion.of(context, Motion.fast),
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: radio ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: radio ? null : BorderRadius.circular(6),
                color: !radio && selected ? AppColors.gold : Colors.transparent,
                border: Border.all(
                    color: selected ? AppColors.gold : AppColors.textTertiary.withValues(alpha: 0.6), width: radio && selected ? 6 : 1.6),
              ),
              child: !radio && selected ? const Icon(TablerIcons.check, size: 13, color: ink) : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(TextSpan(children: [
                TextSpan(text: label),
                if (detail != null)
                  TextSpan(text: '  $detail', style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ]), style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
            ),
            Text(price, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ]),
        ),
      ),
    );
  }
}

/// The highlighted review: the newest five-star review with a comment.
class _ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;
  const _ReviewCard({required this.review});

  String _ago(DateTime? t) {
    if (t == null) return '';
    final d = DateTime.now().difference(t).inDays;
    if (d < 1) return 'today';
    if (d < 7) return '$d ${d == 1 ? 'day' : 'days'} ago';
    if (d < 60) return '${d ~/ 7} ${d ~/ 7 == 1 ? 'week' : 'weeks'} ago';
    return '${d ~/ 30} months ago';
  }

  @override
  Widget build(BuildContext context) {
    final client = review['client'] as Map? ?? {};
    final full = (client['full_name'] ?? 'Client').toString().trim();
    final parts = full.split(RegExp(r'\s+'));
    // First name and initial only.
    final shown = parts.length > 1 ? '${parts.first} ${parts.last[0]}.' : parts.first;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppColors.isDark ? const Color(0xFF1E1912) : const Color(0xFF141210),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PersonAvatar(name: full, url: client['avatar_url'] as String?, size: 32),
          const SizedBox(width: 10),
          Expanded(
            child: Text(shown, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: Color(0xFFF7F3EC))),
          ),
          const Text('★★★★★', style: TextStyle(color: AppColors.gold, letterSpacing: 2, fontSize: 13)),
        ]),
        const SizedBox(height: 10),
        Text('"${(review['comment'] ?? '').toString().trim()}"',
            maxLines: 5,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, height: 1.45, color: Color(0xFFE8E0D2))),
        const SizedBox(height: 8),
        Text(_ago(DateTime.tryParse((review['created_at'] ?? '').toString())?.toLocal()),
            style: const TextStyle(fontSize: 12, color: Color(0xFFA39A8D))),
      ]),
    );
  }
}

class _GalleryViewerScreen extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final int initialIndex;
  final String proName;
  final void Function(Map<String, dynamic> image)? onBook;
  const _GalleryViewerScreen({required this.images, required this.initialIndex, required this.proName, this.onBook});
  @override
  State<_GalleryViewerScreen> createState() => _GalleryViewerScreenState();
}

class _GalleryViewerScreenState extends State<_GalleryViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;
  final _zoom = TransformationController();
  double _drag = 0; // pull-down-to-close offset

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _zoom.dispose();
    super.dispose();
  }

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  void _goTo(int i) {
    Haptics.light();
    _pageController.animateToPage(i, duration: Motion.of(context), curve: Motion.curve);
  }

  @override
  Widget build(BuildContext context) {
    final img = widget.images[_currentIndex];
    final category = ((img['service_categories'] as Map?)?['name'] ?? '').toString();
    final caption = (img['caption'] as String? ?? '').trim();
    final fade = (1 - (_drag.abs() / 400)).clamp(0.3, 1.0);

    return Scaffold(
      backgroundColor: Colors.black.withValues(alpha: fade),
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            child: Row(children: [
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(context),
                style: IconButton.styleFrom(backgroundColor: const Color(0x24FFFFFF)),
                icon: const Icon(TablerIcons.x, color: Colors.white),
              ),
              Expanded(
                child: Text('${_currentIndex + 1} of ${widget.images.length}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 48),
            ]),
          ),
          Expanded(
            // Pull down to close (when not zoomed in).
            child: GestureDetector(
              onVerticalDragUpdate: _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
              onVerticalDragEnd: _zoomed
                  ? null
                  : (d) {
                      if (_drag.abs() > 120 || (d.primaryVelocity ?? 0).abs() > 900) {
                        Haptics.light();
                        Navigator.pop(context);
                      } else {
                        setState(() => _drag = 0);
                      }
                    },
              child: Transform.translate(
                offset: Offset(0, _drag),
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: widget.images.length,
                  onPageChanged: (i) {
                    _zoom.value = Matrix4.identity();
                    setState(() => _currentIndex = i);
                  },
                  itemBuilder: (_, i) => InteractiveViewer(
                    transformationController: i == _currentIndex ? _zoom : null,
                    minScale: 1,
                    maxScale: 4,
                    child: Center(
                      child: Image.network(
                        widget.images[i]['image_url'],
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const Icon(TablerIcons.photo_off, color: Colors.white38, size: 64),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          Opacity(
            opacity: fade,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text(caption.isNotEmpty ? caption : (category.isNotEmpty ? category : 'Work by ${widget.proName}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text([if (category.isNotEmpty && caption.isNotEmpty) category, 'By ${widget.proName}'].join(' · '),
                    style: const TextStyle(color: Color(0xFFB9B0A2), fontSize: 13)),
                if (widget.images.length > 1) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 52,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.images.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (_, i) => GestureDetector(
                        onTap: () => _goTo(i),
                        child: AnimatedOpacity(
                          duration: Motion.of(context, Motion.fast),
                          opacity: i == _currentIndex ? 1 : 0.5,
                          child: Container(
                            width: 52,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(10),
                              border: i == _currentIndex ? Border.all(color: AppColors.gold, width: 2) : null,
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: Image.network(widget.images[i]['image_url'], fit: BoxFit.cover, cacheWidth: 160,
                                errorBuilder: (_, _, _) => const SizedBox()),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
                if (widget.onBook != null) ...[
                  const SizedBox(height: 14),
                  FilledButton(
                    onPressed: () => widget.onBook!(img),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.gold,
                      foregroundColor: const Color(0xFF17130E),
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: const Text('Book this style'),
                  ),
                ],
              ]),
            ),
          ),
        ]),
      ),
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
