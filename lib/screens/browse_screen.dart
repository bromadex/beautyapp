import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  List<Map<String, dynamic>> _providers = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProviders();
  }

  Future<void> _loadProviders() async {
    final data = await supabase
        .from('provider_profiles')
        .select('*, profiles(full_name, location)')
        .eq('is_hidden', false);

    setState(() {
      _providers = List<Map<String, dynamic>>.from(data);
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Browse Stylists')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _providers.isEmpty
              ? const Center(child: Text('No stylists available yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _providers.length,
                  itemBuilder: (_, i) {
                    final p = _providers[i];
                    final name = p['profiles']?['full_name'] ?? 'Stylist';
                    final location = p['profiles']?['location'] ?? '';
                    final status = p['availability_status'] ?? 'offline';

                    Color statusColor;
                    switch (status) {
                      case 'available': statusColor = Colors.green; break;
                      case 'busy':      statusColor = Colors.orange; break;
                      default:          statusColor = Colors.grey;
                    }

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        leading: CircleAvatar(
                          radius: 28,
                          backgroundColor: Colors.pink.shade100,
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : '?',
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(name,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 16)),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (location.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(location,
                                  style: const TextStyle(fontSize: 13)),
                            ],
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Container(
                                  width: 8, height: 8,
                                  decoration: BoxDecoration(
                                    color: statusColor,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  status[0].toUpperCase() + status.substring(1),
                                  style: TextStyle(
                                      color: statusColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => context.push('/provider/${p['provider_id']}'),
                      ),
                    );
                  },
                ),
    );
  }
}