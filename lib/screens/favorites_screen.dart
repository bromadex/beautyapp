import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

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
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
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
                                Icon(Icons.favorite_border,
                                    size: 64, color: Colors.grey.shade400),
                                const SizedBox(height: 16),
                                const Text('No favourites yet',
                                    style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                const Text(
                                    'Save your favourite stylists for quick booking.',
                                    style: TextStyle(
                                        color: Colors.grey, fontSize: 14)),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                  onPressed: () => context.go('/browse'),
                                  icon: const Icon(Icons.search),
                                  label: const Text('Browse Stylists'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _favorites.length,
                      itemBuilder: (_, i) {
                        final fav = _favorites[i];
                        final providerId = fav['provider_id'] as String;
                        final profile =
                            fav['profiles'] as Map<String, dynamic>?;
                        final pp = fav['provider_profiles']
                            as Map<String, dynamic>?;
                        final name = profile?['full_name'] ?? 'Stylist';
                        final location = profile?['location'] ?? '';
                        final status =
                            pp?['availability_status'] ?? 'offline';
                        final rating =
                            (pp?['average_rating'] as num?)?.toDouble() ??
                                0.0;
                        final totalReviews = pp?['total_reviews'] ?? 0;
                        final isHidden = pp?['is_hidden'] == true;

                        // Check subscription
                        final subs = fav['subscriptions'];
                        bool subExpired = true;
                        if (subs is List && subs.isNotEmpty) {
                          subExpired = subs.first['status'] != 'active';
                        }

                        final bool canBook = !isHidden &&
                            !subExpired &&
                            status != 'offline';

                        Color statusColor;
                        String statusLabel;
                        switch (status) {
                          case 'available':
                            statusColor = Colors.green;
                            statusLabel = 'Available';
                            break;
                          case 'busy':
                            statusColor = Colors.orange;
                            statusLabel = 'Busy';
                            break;
                          default:
                            statusColor = Colors.grey;
                            statusLabel = 'Offline';
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 26,
                                      backgroundColor:
                                          Colors.pink.shade100,
                                      child: Text(
                                        name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?',
                                        style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(name,
                                              style: const TextStyle(
                                                  fontWeight:
                                                      FontWeight.bold,
                                                  fontSize: 16)),
                                          if (location.isNotEmpty)
                                            Text(location,
                                                style: const TextStyle(
                                                    color: Colors.grey,
                                                    fontSize: 13)),
                                          const SizedBox(height: 4),
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
                                              const SizedBox(width: 6),
                                              Text(statusLabel,
                                                  style: TextStyle(
                                                      color: statusColor,
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w600)),
                                              if (totalReviews > 0) ...[
                                                const SizedBox(width: 12),
                                                Icon(Icons.star,
                                                    size: 14,
                                                    color: Colors
                                                        .amber.shade700),
                                                const SizedBox(width: 2),
                                                Text(
                                                  '${rating.toStringAsFixed(1)} ($totalReviews)',
                                                  style: const TextStyle(
                                                      fontSize: 12,
                                                      color: Colors.grey),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.favorite,
                                          color: Colors.red),
                                      onPressed: () =>
                                          _removeFavorite(providerId),
                                    ),
                                  ],
                                ),
                                if (subExpired) ...[
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.red.shade50,
                                      borderRadius:
                                          BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'Subscription expired',
                                      style: TextStyle(
                                          color: Colors.red.shade700,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton.icon(
                                    onPressed: canBook
                                        ? () => context.push(
                                            '/provider/$providerId')
                                        : null,
                                    icon: const Icon(
                                        Icons.calendar_month_outlined,
                                        size: 18),
                                    label: const Text('Book Again'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}
