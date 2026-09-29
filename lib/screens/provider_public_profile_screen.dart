import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../services/guest_service.dart';
import '../widgets/ui.dart';

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
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
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
              child: Icon(Icons.lock_outline_rounded,
                  color: AppColors.primary, size: 36),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'Sign in to $action',
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'Create a free account or sign in to book appointments, save favorites, and more.',
              textAlign: TextAlign.center,
              style: const TextStyle(
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
      ),
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
            .select('*, service_categories(name, icon), service_tiers(name, price, duration_minutes, is_active, sort_order)')
            .eq('provider_id', id)
            .eq('is_active', true)
            .order('created_at');
        _services = List<Map<String, dynamic>>.from(servicesResponse);
      } catch (e) {
        _services = [];
      }


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
      context: context,
      builder: (_) => Padding(
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
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Provider Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: AppColors.error),
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
    String statusLabel;
    switch (status) {
      case 'available':
        statusColor = AppColors.available;
        statusLabel = 'Available';
        break;
      case 'busy':
        statusColor = AppColors.busy;
        statusLabel = 'Currently Busy';
        break;
      default:
        statusColor = AppColors.offline;
        statusLabel = 'Offline';
    }

    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = (_providerProfile?['total_reviews'] as num?)?.toInt() ?? 0;
    final idVerified = _profile?['is_verified'] == true;
    final bizVerified = _profile?['is_business_verified'] == true;
    final location = address.isNotEmpty ? address : (_profile?['location'] ?? '').toString();
    final isSelf = _isLoggedIn && supabase.auth.currentUser!.id == widget.providerId;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            actions: [
              if (_providerProfile?['slug'] != null)
                IconButton(
                  icon: const Icon(Icons.ios_share_rounded),
                  tooltip: 'Share',
                  onPressed: () => _share(name),
                ),
              if (!isSelf)
                ScaleTransition(
                  scale: _heartScale,
                  child: IconButton(
                    icon: Icon(
                      _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _isFavorited ? AppColors.accent : AppColors.textPrimary,
                    ),
                    tooltip: _isFavorited ? 'Remove from favourites' : 'Save to favourites',
                    onPressed: _toggleFavorite,
                  ),
                ),
              const SizedBox(width: 8),
            ],
          ),

          SliverToBoxAdapter(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Column(children: [
                    Stack(children: [
                      PersonAvatar(name: name, url: _profile?['avatar_url'], size: 104),
                      Positioned(
                        right: 6,
                        bottom: 6,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: AppColors.surfaceLight, width: 3),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    Text(name, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
                    if (location.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.location_on_outlined, size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(location,
                              style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis),
                        ),
                      ]),
                    ],
                    const SizedBox(height: 12),
                    Wrap(alignment: WrapAlignment.center, spacing: 6, runSpacing: 6, children: [
                      Pill(label: statusLabel, color: statusColor),
                      if (idVerified) const Pill(label: 'ID verified', color: AppColors.info, icon: Icons.verified_rounded),
                      if (bizVerified)
                        const Pill(label: 'Verified business', color: AppColors.success, icon: Icons.storefront_rounded),
                    ]),
                    const SizedBox(height: 20),

                    // Stats
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppRadius.lgAll,
                        border: Border.all(color: AppColors.border),
                      ),
                      child: IntrinsicHeight(
                        child: Row(children: [
                          Expanded(
                            child: _Stat(
                              value: total == 0 ? '—' : avg.toStringAsFixed(1),
                              label: 'Rating',
                              icon: Icons.star_rounded,
                              onTap: total == 0 ? null : () => context.push('/provider/${widget.providerId}/reviews'),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(
                            child: _Stat(
                              value: '$total',
                              label: total == 1 ? 'Review' : 'Reviews',
                              onTap: total == 0 ? null : () => context.push('/provider/${widget.providerId}/reviews'),
                            ),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _Stat(value: '${_services.length}', label: 'Services')),
                        ]),
                      ),
                    ),
                    if (_loyalty?['enabled'] == true) ...[
                      const SizedBox(height: 12),
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
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!_isLoggedIn) ...[
                    SoftBanner(
                      icon: Icons.person_outline_rounded,
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
                      style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                  ],

                  // Services
                  Text('Services & Prices', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.md),
                  if (_services.isEmpty)
                    Text(
                      'No services listed yet.',
                      style: TextStyle(color: AppColors.textTertiary),
                    )
                  else
                    ..._services.map((s) {
                      final cat = s['service_categories'] as Map?;
                      return GestureDetector(
                        onTap: () => _showServiceDetails(s),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.cardLight,
                            border: Border.all(color: AppColors.border),
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Row(
                            children: [
                              if (s['image_url'] != null)
                                ClipRRect(
                                  borderRadius: AppRadius.smAll,
                                  child: Image.network(s['image_url'], width: 48, height: 48, fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) => const SizedBox(width: 48, height: 48)),
                                )
                              else
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: AppRadius.smAll,
                                ),
                                child: Center(
                                  child: Icon(categoryIcon(cat?['name']),
                                      size: 20, color: AppColors.primary),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      s['service_name'],
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${cat?['name'] ?? ''} · ${s['duration_minutes']} min',
                                      style: const TextStyle(fontSize: 13, color: AppColors.textTertiary),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                _priceLabel(s),
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 17,
                                  color: AppColors.primary,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textTertiary),
                            ],
                          ),
                        ),
                      );
                    }),


                  const SizedBox(height: AppSpacing.xxl),

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
                                child: Icon(Icons.broken_image, color: AppColors.textTertiary),
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
      context: context,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).padding.bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Share $name', style: Theme.of(ctx).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(link, style: Theme.of(ctx).textTheme.bodyMedium),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              launchUrl(Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Book $name on BeauTap: $link')}'),
                  mode: LaunchMode.externalApplication);
            },
            icon: const Icon(Icons.chat_rounded, size: 18),
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
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy link'),
          ),
        ]),
      ),
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
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.primary)),
              if (desc.isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(desc, style: const TextStyle(fontSize: 14.5, height: 1.5, color: AppColors.textSecondary)),
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
                          style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
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
                      const Icon(Icons.check_circle_rounded, size: 18, color: AppColors.success),
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
                    const Row(children: [
                      Icon(Icons.spa_outlined, size: 18, color: AppColors.primary),
                      SizedBox(width: 6),
                      Text('Aftercare', style: TextStyle(fontWeight: FontWeight.w700)),
                    ]),
                    const SizedBox(height: 6),
                    Text(aftercare, style: const TextStyle(fontSize: 14, height: 1.5, color: AppColors.textSecondary)),
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
    return Container(
      padding: EdgeInsets.only(
        left: AppSpacing.xl,
        right: AppSpacing.xl,
        top: AppSpacing.md,
        bottom: MediaQuery.of(context).padding.bottom + AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: status == 'available'
          ? FilledButton.icon(
              onPressed: _services.isEmpty ? null : () => _showServicePicker(context),
              icon: const Icon(Icons.calendar_month_outlined),
              label: Text(_isLoggedIn ? 'Book Appointment' : 'Sign In to Book'),
              style: FilledButton.styleFrom(
                minimumSize: const Size(double.infinity, 52),
              ),
            )
          : Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: status == 'busy'
                    ? AppColors.busy.withValues(alpha: 0.1)
                    : AppColors.surfaceLight,
                borderRadius: AppRadius.mdAll,
                border: Border.all(
                  color: status == 'busy'
                      ? AppColors.busy.withValues(alpha: 0.3)
                      : AppColors.border,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: status == 'busy' ? AppColors.busy : AppColors.offline,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    status == 'busy'
                        ? 'This provider is currently busy'
                        : 'This provider is currently offline',
                    style: TextStyle(
                      color: status == 'busy' ? AppColors.busy : AppColors.textTertiary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
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
                        Icons.broken_image,
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

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  const _Stat({required this.value, required this.label, this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[Icon(icon, size: 18, color: AppColors.secondary), const SizedBox(width: 3)],
          Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 2),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: available ? AppColors.success.withValues(alpha: 0.08) : AppColors.primary.withValues(alpha: 0.05),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: available ? AppColors.success.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.loyalty_rounded, size: 18, color: available ? AppColors.success : AppColors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              available ? 'Your next booking is $pct% off' : 'Loyalty card: every ${needed}th visit $pct% off'
                  .replaceFirst('every 2th', 'every 2nd').replaceFirst('every 3th', 'every 3rd'),
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
            ),
          ),
        ]),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (var i = 0; i < stamps; i++)
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < progress || available ? AppColors.primary : Colors.white,
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.5)),
              ),
              child: i < progress || available ? const Icon(Icons.check_rounded, size: 14, color: Colors.white) : null,
            ),
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: available ? AppColors.success : Colors.white,
              border: Border.all(color: AppColors.success),
            ),
            child: Icon(Icons.card_giftcard_rounded, size: 13, color: available ? Colors.white : AppColors.success),
          ),
        ]),
        if (!available) ...[
          const SizedBox(height: 8),
          Text('${stamps - progress} more ${stamps - progress == 1 ? 'visit' : 'visits'} to your reward. Applied automatically.',
              style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ],
      ]),
    );
  }
}
