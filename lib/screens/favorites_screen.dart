import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

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

    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('favorites')
        .select('*, profiles!favorites_provider_id_fkey(full_name, location), '
            'provider_profiles!inner(availability_status, average_rating, total_reviews, is_hidden), '
            'subscriptions:subscriptions!subscriptions_provider_id_fkey(status)')
        .eq('client_id', userId)
        .order('created_at', ascending: false);

    if (mounted) {
      setState(() {
        _favorites = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<void> _removeFavorite(String providerId) async {
    final userId = supabase.auth.currentUser!.id;
    await supabase
        .from('favorites')
        .delete()
        .eq('client_id', userId)
        .eq('provider_id', providerId);
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Favourite Stylists')),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                                    Icons.favorite_border_rounded,
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
                                const Text(
                                  'Save your favourite stylists for quick booking.',
                                  style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
                                ),
                                const SizedBox(height: AppSpacing.xxl),
                                FilledButton.icon(
                                  onPressed: () => context.go('/browse'),
                                  icon: const Icon(Icons.search_rounded),
                                  label: const Text('Browse Stylists'),
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
                        final name = profile?['full_name'] ?? 'Stylist';
                        final location = profile?['location'] ?? '';
                        final status = pp?['availability_status'] ?? 'offline';
                        final rating = (pp?['average_rating'] as num?)?.toDouble() ?? 0.0;
                        final totalReviews = pp?['total_reviews'] ?? 0;
                        final isHidden = pp?['is_hidden'] == true;

                        // Check subscription
                        final subs = fav['subscriptions'];
                        bool subExpired = true;
                        if (subs is List && subs.isNotEmpty) {
                          subExpired = subs.first['status'] != 'active';
                        }

                        final bool canBook = !isHidden && !subExpired && status != 'offline';

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
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Padding(
                              padding: AppSpacing.cardPadding,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      // Gradient avatar
                                      Container(
                                        width: 52,
                                        height: 52,
                                        decoration: const BoxDecoration(
                                          gradient: AppColors.primaryGradient,
                                          shape: BoxShape.circle,
                                        ),
                                        child: Center(
                                          child: Text(
                                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                                            style: const TextStyle(
                                              fontSize: 20,
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ),
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
                                                  Icon(Icons.location_on_outlined, size: 14, color: AppColors.textTertiary),
                                                  const SizedBox(width: 2),
                                                  Expanded(
                                                    child: Text(
                                                      location,
                                                      style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
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
                                                  Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                                                  const SizedBox(width: 2),
                                                  Text(
                                                    '${rating.toStringAsFixed(1)} ($totalReviews)',
                                                    style: const TextStyle(
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
                                        icon: Icon(Icons.favorite_rounded, color: AppColors.accent, size: 26),
                                        tooltip: 'Remove from favourites',
                                        onPressed: () => _removeFavorite(providerId),
                                      ),
                                    ],
                                  ),

                                  if (subExpired) ...[
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
                                        'Subscription expired',
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
                                      icon: const Icon(Icons.calendar_month_outlined, size: 18),
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
