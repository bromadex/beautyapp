import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/star_rating_widget.dart';
import '../widgets/review_card.dart';

class ProviderReviewsScreen extends StatefulWidget {
  final String providerId;
  const ProviderReviewsScreen({super.key, required this.providerId});

  @override
  State<ProviderReviewsScreen> createState() => _ProviderReviewsScreenState();
}

class _ProviderReviewsScreenState extends State<ProviderReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  Map<String, dynamic>? _providerProfile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        supabase
            .from('provider_profiles')
            .select('average_rating, total_reviews')
            .eq('provider_id', widget.providerId)
            .maybeSingle(),
        supabase
            .from('reviews')
            .select('*, client:profiles!reviews_client_id_fkey(full_name)')
            .eq('provider_id', widget.providerId)
            .order('created_at', ascending: false),
      ]);

      setState(() {
        _providerProfile = results[0] as Map<String, dynamic>?;
        _reviews = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reviews: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  /// Build the star distribution bars (5 down to 1).
  Map<int, int> get _ratingDistribution {
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _reviews) {
      final star = (r['rating'] as num?)?.toInt() ?? 0;
      if (star >= 1 && star <= 5) dist[star] = dist[star]! + 1;
    }
    return dist;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = _providerProfile?['total_reviews'] ?? 0;
    final dist = _ratingDistribution;
    final maxCount = dist.values.fold(0, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: Column(
        children: [
          // Rating summary card
          Container(
            margin: const EdgeInsets.all(AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: AppColors.cardLight,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                // Large rating number
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Text(
                        avg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      StarRatingWidget(rating: avg, size: 22),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$total review${total == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.lg),

                // Distribution bars
                Expanded(
                  flex: 3,
                  child: Column(
                    children: List.generate(5, (i) {
                      final star = 5 - i;
                      final count = dist[star] ?? 0;
                      final fraction = maxCount > 0 ? count / maxCount : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '$star',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: AppRadius.smAll,
                                child: LinearProgressIndicator(
                                  value: fraction,
                                  minHeight: 6,
                                  backgroundColor: AppColors.surfaceLight,
                                  valueColor: AlwaysStoppedAnimation(AppColors.warning),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Text(
                  'All Reviews',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '$total total',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Reviews list
          Expanded(
            child: _reviews.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.rate_review_outlined, size: 56, color: AppColors.textTertiary),
                        const SizedBox(height: AppSpacing.lg),
                        const Text(
                          'No reviews yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Be the first to leave a review!',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _reviews.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) => ReviewCard(review: _reviews[i]),
                  ),
          ),
        ],
      ),
    );
  }
}
