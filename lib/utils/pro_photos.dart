import '../supabase_client.dart';

/// Each pro's newest approved work photo, by provider id, for cards on Home
/// and Browse. Pros without one fall back to their profile photo, then to a
/// pastel tile (see ProPhoto).
Future<Map<String, String>> loadCoverPhotos() async {
  try {
    final rows = await supabase
        .from('hairstyle_gallery')
        .select('provider_id, image_url')
        .eq('is_approved', true)
        .order('uploaded_at', ascending: false)
        .limit(500);
    final covers = <String, String>{};
    for (final r in rows) {
      final id = r['provider_id'] as String?;
      final url = r['image_url'] as String?;
      if (id != null && url != null && url.isNotEmpty) covers.putIfAbsent(id, () => url);
    }
    return covers;
  } catch (_) {
    return {};
  }
}

/// The best photo to show for a pro on a card.
String? coverFor(Map<String, String> covers, String providerId, String? avatarUrl) =>
    covers[providerId] ?? ((avatarUrl ?? '').isNotEmpty ? avatarUrl : null);
