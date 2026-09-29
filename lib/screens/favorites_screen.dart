import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen> {
  List<Map<String, dynamic>> _favorites = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final data = await supabase
          .from('favorites')
          .select('*, profiles!favorites_provider_id_fkey(full_name, location, avatar_url)')
          .eq('client_id', userId)
          .order('created_at', ascending: false);

      final favorites = List<Map<String, dynamic>>.from(data);

      for (final fav in favorites) {
        final pid = fav['provider_id'] as String;
        try {
          final pp = await supabase
              .from('provider_profiles')
              .select('availability_status, average_rating, total_reviews, is_hidden')
              .eq('provider_id', pid)
              .maybeSingle();
          fav['provider_profiles'] = pp;
        } catch (_) {}
      }

      if (mounted) {
        setState(() {
          _favorites = favorites;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeFavorite(String providerId) async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      await supabase
          .from('favorites')
          .delete()
          .eq('client_id', userId)
          .eq('provider_id', providerId);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourite pros')),
      body: _loading
          ? const LoadingPlaceholder()
          : RefreshIndicator(
              color: AppColors.primary,
              onRefresh: _load,
              child: _favorites.isEmpty
                  ? ListView(
                      children: [
                        SizedBox(
                          height: MediaQuery.of(context).size.height * 0.6,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  width: 80,
                                  height: 80,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.08),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    TablerIcons.heart,
                                    size: 40,
                                    color: AppColors.primary.withValues(alpha: 0.5),
                                  ),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                Text(
                                  'No favourites yet',
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                Text(
                                  'Save your favourite beauty pros for quick booking.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                FilledButton.icon(
                                  onPressed: () => context.go('/browse'),
                                  icon: const Icon(TablerIcons.search),
                                  label: const Text('Browse beauty pros'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      itemCount: _favorites.length,
                      itemBuilder: (_, i) {
                        final fav = _favorites[i];
                        final providerId = fav['provider_id'] as String;
                        final profile = fav['profiles'] as Map<String, dynamic>?;
                        final pp = fav['provider_profiles'] as Map<String, dynamic>?;
                        final name = profile?['full_name'] ?? 'Beauty pro';
                        final avatarUrl = profile?['avatar_url'] as String?;
                        final location = profile?['location'] ?? '';
                        final status = pp?['availability_status'] ?? 'offline';
                        final rating = (pp?['average_rating'] as num?)?.toDouble() ?? 0.0;
                        final totalReviews = pp?['total_reviews'] ?? 0;
                        final isHidden = pp?['is_hidden'] == true;

                        final bool canBook = !isHidden;

                        Color statusColor;
                        String statusLabel;
                        switch (status) {
                          case 'available':
                            statusColor = AppColors.available;
                            statusLabel = 'Available';
                            break;
                          case 'busy':
                            statusColor = AppColors.busy;
                            statusLabel = 'Busy';
                            break;
                          default:
                            statusColor = AppColors.offline;
                            statusLabel = 'Offline';
                        }

                        return Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Container(
                            decoration: BoxDecoration(
                              color: AppColors.cardLight,
                              borderRadius: AppRadius.lgAll,
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Padding(
                              padding: AppSpacing.cardPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      PersonAvatar(name: name, url: avatarUrl, size: 52),
                                      const SizedBox(width: AppSpacing.lg),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(name, style: Theme.of(context).textTheme.titleMedium),
                                            if (location.isNotEmpty) ...[
                                              const SizedBox(height: 2),
                                              Row(
                                                children: [
                                                  Icon(TablerIcons.map_pin, size: 14, color: AppColors.textTertiary),
                                                  const SizedBox(width: 2),
                                                  Expanded(
                                                    child: Text(
                                                      location,
                                                      style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                            const SizedBox(height: AppSpacing.xs),
                                            Row(
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
                                                  style: TextStyle(
                                                    color: statusColor,
                                                    fontSize: 12,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                                if (totalReviews > 0) ...[
                                                  const SizedBox(width: AppSpacing.md),
                                                  Icon(TablerIcons.star_filled, size: 14, color: AppColors.warning),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${rating.toStringAsFixed(1)} ($totalReviews)',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      color: AppColors.textSecondary,
                                                    ),
                                                  ),
                                                ],
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      // Favorite heart button
                                      IconButton(
                                        icon: Icon(TablerIcons.heart_filled, color: AppColors.accent, size: 26),
                                        tooltip: 'Remove from favourites',
                                        onPressed: () => _removeFavorite(providerId),
                                      ),
                                    ],
                                  ),

                                  if (isHidden) ...[
                                    const SizedBox(height: AppSpacing.sm),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: AppSpacing.sm,
                                        vertical: AppSpacing.xs,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.error.withValues(alpha: 0.08),
                                        borderRadius: AppRadius.smAll,
                                      ),
                                      child: Text(
                                        'Not taking bookings right now',
                                        style: TextStyle(
                                          color: AppColors.error,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: AppSpacing.md),

                                  // Book Again button
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton.icon(
                                      onPressed: canBook
                                          ? () => context.push('/provider/$providerId')
                                          : null,
                                      icon: const Icon(TablerIcons.calendar_month, size: 18),
                                      label: const Text('Book Again'),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
