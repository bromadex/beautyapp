import 'package:flutter/material.dart';
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
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Colors.pink.shade100,
                  child: Text(
                    clientName.isNotEmpty ? clientName[0].toUpperCase() : '?',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clientName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                      Text(dateStr,
                          style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  ),
                ),
                StarRatingWidget(rating: rating, size: 18),
              ],
            ),

            // Comment
            if (comment.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(comment, style: const TextStyle(fontSize: 14, height: 1.5)),
            ],

            // After-service photo
            if (imageUrl != null && imageUrl.isNotEmpty) ...[
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
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