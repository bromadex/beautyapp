import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../widgets/star_rating_widget.dart';

class ProviderPublicProfileScreen extends StatefulWidget {
  final String providerId;
  const ProviderPublicProfileScreen({super.key, required this.providerId});
  @override
  State<ProviderPublicProfileScreen> createState() =>
      _ProviderPublicProfileScreenState();
}

class _ProviderPublicProfileScreenState
    extends State<ProviderPublicProfileScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _providerProfile;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _gallery = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
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
            .eq('is_approved', true) // Only show approved photos
            .order('uploaded_at', ascending: false);
        _gallery = List<Map<String, dynamic>>.from(galleryResponse);
      } catch (e) {
        _gallery = [];
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

  void _showServicePicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Select a Service',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            ..._services.map((s) {
              final cat = s['service_categories'] as Map?;
              return ListTile(
                leading: Text(cat?['icon'] ?? '✂️',
                    style: const TextStyle(fontSize: 22)),
                title: Text(s['service_name']),
                subtitle: Text('${s['duration_minutes']} min'),
                trailing: Text('\$${s['price']}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                onTap: () {
                  Navigator.pop(context);
                  context.push('/book/${widget.providerId}/${s['id']}');
                },
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
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Provider Profile')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
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
        statusColor = Colors.green;
        statusLabel = '🟢 Available';
        break;
      case 'busy':
        statusColor = Colors.orange;
        statusLabel = '🟠 Currently Busy';
        break;
      default:
        statusColor = Colors.grey;
        statusLabel = '⚫ Offline';
    }

    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor)),
            ),
            const SizedBox(height: 8),

            // Star rating + reviews link (Stage 9)
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
                  return const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text('No reviews yet',
                        style: TextStyle(color: Colors.grey, fontSize: 13)),
                  );
                }
                return GestureDetector(
                  onTap: () => context.push('/provider/${widget.providerId}/reviews'),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Row(
                      children: [
                        StarRatingWidget(rating: avg, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          '${avg.toStringAsFixed(1)} ($total review${total == 1 ? '' : 's'})',
                          style: const TextStyle(
                              fontSize: 13,
                              color: Colors.grey,
                              decoration: TextDecoration.underline),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            const SizedBox(height: 8),

            // Address
            if (address.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.location_on_outlined, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
            ],

            // Bio
            if (bio.isNotEmpty) ...[
              const Text(
                'About',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(bio, style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 24),
            ],

            // Services
            const Text(
              'Services & Prices',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_services.isEmpty)
              const Text(
                'No services listed yet.',
                style: TextStyle(color: Colors.grey),
              )
            else
              ..._services.map((s) {
                final cat = s['service_categories'] as Map?;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade200),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Text(
                        cat?['icon'] ?? '✂️',
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              s['service_name'],
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            Text(
                              '${cat?['name'] ?? ''} · ${s['duration_minutes']} min',
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '\$${s['price']}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),

            const SizedBox(height: 24),

            // Gallery
            const Text(
              'Gallery',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 12),
            if (_gallery.isEmpty)
              const Text(
                'No gallery photos yet.',
                style: TextStyle(color: Colors.grey),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 6,
                  mainAxisSpacing: 6,
                ),
                itemCount: _gallery.length,
                itemBuilder: (_, i) {
                  final img = _gallery[i];
                  return ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      img['image_url'],
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) =>
                          const Icon(Icons.broken_image),
                    ),
                  );
                },
              ),

            const SizedBox(height: 40),

            // Book button
            if (status == 'available')
              FilledButton.icon(
                onPressed: _services.isEmpty
                    ? null
                    : () => _showServicePicker(context),
                icon: const Icon(Icons.calendar_month_outlined),
                label: const Text('Book Appointment'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(double.infinity, 52),
                ),
              )
            else if (status == 'busy')
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: const Text(
                  '🟠 This provider is currently busy',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange),
                ),
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '⚫ This provider is currently offline',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}