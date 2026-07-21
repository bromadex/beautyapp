import '../supabase_client.dart';

class SmartMatchService {
  static Future<List<Map<String, dynamic>>> getRecommendations({
    required String clientId,
    int limit = 10,
  }) async {
    final providers = await supabase
        .from('provider_profiles')
        .select('*, profiles(id, full_name, location)')
        .or('is_hidden.eq.false,is_hidden.is.null');
    final providerList = List<Map<String, dynamic>>.from(providers);

    // Client's past bookings for preference learning
    final pastBookings = await supabase
        .from('bookings')
        .select('provider_id, services(category_id, price), status')
        .eq('client_id', clientId);
    final pastList = List<Map<String, dynamic>>.from(pastBookings);

    // Client's favorites
    final favorites = await supabase
        .from('favorites')
        .select('provider_id')
        .eq('user_id', clientId);
    final favIds = (favorites as List).map((f) => f['provider_id']).toSet();

    // Client's reviews (to find preferred providers)
    final clientReviews = await supabase
        .from('reviews')
        .select('provider_id, rating')
        .eq('client_id', clientId);
    final reviewMap = <String, double>{};
    for (final r in List<Map<String, dynamic>>.from(clientReviews)) {
      reviewMap[r['provider_id']] = (r['rating'] as num).toDouble();
    }

    // Preferred categories from past bookings
    final categoryCounts = <String, int>{};
    final pricePoints = <double>[];
    final bookedProviderIds = <String>{};
    for (final b in pastList) {
      final pid = b['provider_id'];
      if (pid != null) bookedProviderIds.add(pid);
      final catId = b['services']?['category_id'];
      if (catId != null) {
        categoryCounts[catId] = (categoryCounts[catId] ?? 0) + 1;
      }
      final price = (b['services']?['price'] as num?)?.toDouble();
      if (price != null) pricePoints.add(price);
    }

    final avgPrice = pricePoints.isNotEmpty
        ? pricePoints.reduce((a, b) => a + b) / pricePoints.length
        : 0.0;

    // Score each provider
    List<Map<String, dynamic>> scored = [];
    for (final p in providerList) {
      final pid = p['provider_id'];
      double score = 0;

      // 1. Rating score (0-30 points)
      final rating = (p['average_rating'] as num?)?.toDouble() ?? 0;
      final reviews = (p['total_reviews'] as num?)?.toInt() ?? 0;
      score += (rating / 5.0) * 20;
      // Bonus for review volume (up to 10 pts)
      score += (reviews.clamp(0, 50) / 50.0) * 10;

      // 2. Availability bonus (0-15 points)
      final status = p['availability_status'] ?? 'offline';
      if (status == 'available') {
        score += 15;
      } else if (status == 'busy') {
        score += 5;
      }

      // 3. Favorite bonus (10 points)
      if (favIds.contains(pid)) {
        score += 10;
      }

      // 4. Previously booked & rated highly (0-15 points)
      if (reviewMap.containsKey(pid)) {
        final clientRating = reviewMap[pid]!;
        score += (clientRating / 5.0) * 15;
      }

      // 5. Category match (0-15 points)
      if (categoryCounts.isNotEmpty) {
        try {
          final services = await supabase
              .from('services')
              .select('category_id, price, is_active')
              .eq('provider_id', pid);
          final serviceList = List<Map<String, dynamic>>.from(services);
          p['_services'] = serviceList;

          int categoryMatches = 0;
          for (final s in serviceList) {
            if (s['is_active'] == true && categoryCounts.containsKey(s['category_id'])) {
              categoryMatches += categoryCounts[s['category_id']]!;
            }
          }
          final maxCatCount = categoryCounts.values.fold<int>(0, (a, b) => a > b ? a : b);
          if (maxCatCount > 0) {
            score += (categoryMatches.clamp(0, maxCatCount) / maxCatCount) * 15;
          }

          // 6. Price affinity (0-10 points)
          if (avgPrice > 0 && serviceList.isNotEmpty) {
            final activePrices = serviceList
                .where((s) => s['is_active'] == true)
                .map((s) => (s['price'] as num?)?.toDouble() ?? 0)
                .where((p) => p > 0)
                .toList();
            if (activePrices.isNotEmpty) {
              final provAvg = activePrices.reduce((a, b) => a + b) / activePrices.length;
              final priceDiff = (provAvg - avgPrice).abs();
              final priceScore = (1 - (priceDiff / avgPrice).clamp(0, 1)) * 10;
              score += priceScore;
            }
          }
        } catch (_) {}
      }

      // 7. Newness penalty for providers with zero reviews (slight)
      if (reviews == 0) score -= 5;

      // 8. Diversity: slight boost for NOT previously booked
      if (!bookedProviderIds.contains(pid) && pastList.isNotEmpty) {
        score += 5;
      }

      p['_matchScore'] = score;
      p['_matchReasons'] = _buildMatchReasons(
        rating: rating,
        reviews: reviews,
        isFavorite: favIds.contains(pid),
        isAvailable: status == 'available',
        categoryMatch: categoryCounts.isNotEmpty,
        previouslyBooked: bookedProviderIds.contains(pid),
        highlyRated: reviewMap.containsKey(pid) && (reviewMap[pid] ?? 0) >= 4,
      );

      scored.add(p);
    }

    scored.sort((a, b) => ((b['_matchScore'] as double)).compareTo(a['_matchScore'] as double));

    return scored.take(limit).toList();
  }

  static List<String> _buildMatchReasons({
    required double rating,
    required int reviews,
    required bool isFavorite,
    required bool isAvailable,
    required bool categoryMatch,
    required bool previouslyBooked,
    required bool highlyRated,
  }) {
    final reasons = <String>[];
    if (isFavorite) reasons.add('In your favourites');
    if (highlyRated) reasons.add('You rated them highly');
    if (isAvailable) reasons.add('Available now');
    if (categoryMatch) reasons.add('Matches your style');
    if (rating >= 4.5 && reviews >= 5) reasons.add('Top rated');
    if (rating >= 4.0 && reviews >= 3 && !reasons.contains('Top rated')) reasons.add('Highly rated');
    if (previouslyBooked && !highlyRated) reasons.add('Booked before');
    if (reasons.isEmpty && reviews > 0) reasons.add('${rating.toStringAsFixed(1)} stars');
    if (reasons.isEmpty) reasons.add('New stylist');
    return reasons.take(3).toList();
  }
}
