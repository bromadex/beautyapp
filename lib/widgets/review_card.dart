import 'package:flutter/material.dart';
import '../theme.dart';
import 'star_rating_widget.dart';

class ReviewCard extends StatelessWidget {
  final Map<String, dynamic> review;

  const ReviewCard({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final clientName = review['client']?['full_name'] ?? 'Client';
    final rating = (review['rating'] as num).toDouble();
    final comment = review['comment'] ?? '';
    final imageUrl = review['after_service_image_url'];
    final createdAt = DateTime.tryParse(review['created_at'] ?? '');
    final dateStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // -- Header --
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor:
                      AppColors.accent.withValues(alpha: 0.15),
                  child: Text(
                    clientName.isNotEmpty
                        ? clientName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clientName,
                          style: Theme.of(context).textTheme.titleSmall),
                      const SizedBox(height: AppSpacing.xs),
                      Text(dateStr,
                          style: Theme.of(context).textTheme.labelSmall),
                    ],
                  ),
                ),
                StarRatingWidget(rating: rating, size: 18),
              ],
            ),

            // -- Comment --
            if (comment.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                comment,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(height: 1.5),
              ),
            ],

            // -- After-service photo --
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.md),
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network(
                  imageUrl,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
