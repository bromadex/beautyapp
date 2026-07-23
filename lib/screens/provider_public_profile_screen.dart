import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/star_rating_widget.dart';

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
                color: Colors.grey.shade300,
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
            const SizedBox(height: AppSpacing.md),
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
            .select('*, service_categories(name, icon)')
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
                  border: Border.all(color: Colors.grey.shade200),
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
                      child: Text(cat?['icon'] ?? '', style: const TextStyle(fontSize: 20)),
                    ),
                  ),
                  title: Text(s['service_name'], style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${s['duration_minutes']} min',
                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                  ),
                  trailing: Text(
                    '\$${s['price']}',
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 220,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              if (!_isLoggedIn || supabase.auth.currentUser!.id != widget.providerId)
                ScaleTransition(
                  scale: _heartScale,
                  child: IconButton(
                    icon: Icon(
                      _isFavorited ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                      color: _isFavorited ? AppColors.accent : Colors.white,
                      size: 28,
                    ),
                    tooltip: _isFavorited ? 'Remove from favorites' : 'Add to favorites',
                    onPressed: _toggleFavorite,
                  ),
                ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                child: SafeArea(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white.withValues(alpha: 0.4), width: 2),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        name,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: AppRadius.xxlAll,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                color: statusColor,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs + 2),
                            Text(
                              statusLabel,
                              style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),
                    ],
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.screenPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sign-in banner for guests
                  if (!_isLoggedIn) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.06),
                        borderRadius: AppRadius.mdAll,
                        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              color: AppColors.primary, size: 20),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              'Sign in to book, save favorites, and chat with this provider.',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          TextButton(
                            onPressed: () => context.go('/login'),
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text('Sign In',
                                style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Rating + reviews
                  FutureBuilder(
                    future: supabase
                        .from('provider_profiles')
                        .select('average_rating, total_reviews')
                        .eq('provider_id', widget.providerId)
                        .maybeSingle(),
                    builder: (context, snapshot) {
                      if (!snapshot.hasData || snapshot.data == null) {
                        return const SizedBox.shrink();
                      }
                      final data = snapshot.data as Map<String, dynamic>;
                      final avg = (data['average_rating'] as num?)?.toDouble() ?? 0.0;
                      final total = data['total_reviews'] ?? 0;
                      if (total == 0) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                          child: Text(
                            'No reviews yet',
                            style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                          ),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                        child: InkWell(
                          borderRadius: AppRadius.smAll,
                          onTap: () => context.push('/provider/${widget.providerId}/reviews'),
                          child: Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.08),
                              borderRadius: AppRadius.mdAll,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                StarRatingWidget(rating: avg, size: 18),
                                const SizedBox(width: AppSpacing.sm),
                                Text(
                                  '${avg.toStringAsFixed(1)} ($total review${total == 1 ? '' : 's'})',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.xs),
                                Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textTertiary),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),

                  // Address
                  if (address.isNotEmpty) ...[
                    Row(
                      children: [
                        Icon(Icons.location_on_outlined, size: 18, color: AppColors.textTertiary),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            address,
                            style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xl),
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
                        onTap: () {
                          if (!_isLoggedIn) {
                            _promptSignIn(action: 'book an appointment');
                          } else {
                            context.push('/book/${widget.providerId}/${s['id']}');
                          }
                        },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: AppSpacing.sm),
                          padding: const EdgeInsets.all(AppSpacing.lg),
                          decoration: BoxDecoration(
                            color: AppColors.cardLight,
                            border: Border.all(color: Colors.grey.shade200),
                            borderRadius: AppRadius.mdAll,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(alpha: 0.1),
                                  borderRadius: AppRadius.smAll,
                                ),
                                child: Center(
                                  child: Text(
                                    cat?['icon'] ?? '',
                                    style: const TextStyle(fontSize: 20),
                                  ),
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
                                '\$${s['price']}',
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
        ],
      ),

      bottomNavigationBar: _buildBottomBar(context, status),
    );
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
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
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
                      : Colors.grey.shade200,
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
