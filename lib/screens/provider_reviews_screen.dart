import 'package:flutter/material.dart';
import '../supabase_client.dart';
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

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = _providerProfile?['total_reviews'] ?? 0;

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: Column(
        children: [
          // Rating summary
          Container(
            padding: const EdgeInsets.all(24),
            color: Colors.pink.shade50,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  avg.toStringAsFixed(1),
                  style: const TextStyle(
                      fontSize: 56, fontWeight: FontWeight.bold, color: Colors.pink),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    StarRatingWidget(rating: avg, size: 28),
                    const SizedBox(height: 6),
                    Text('$total review${total == 1 ? '' : 's'}',
                        style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  ],
                ),
              ],
            ),
          ),

          // Reviews list
          Expanded(
            child: _reviews.isEmpty
                ? const Center(
                    child: Text('No reviews yet', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _reviews.length,
                    itemBuilder: (_, i) => ReviewCard(review: _reviews[i]),
                  ),
          ),
        ],
      ),
    );
  }
}