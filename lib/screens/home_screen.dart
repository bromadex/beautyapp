import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _verification;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _subscription;
  bool _isAdmin = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser!.id;

    final profile = await supabase
        .from('profiles').select().eq('id', userId).single();

    final adminRows = await supabase
        .from('admins').select().eq('user_id', userId);
    final isAdmin = (adminRows as List).isNotEmpty;

    Map<String, dynamic>? verification;
    try {
      verification = await supabase
          .from('verifications').select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1).single();
    } catch (_) {}

    Map<String, dynamic>? providerProfile;
    Map<String, dynamic>? subscription;
    
    if (profile['user_type'] == 'provider') {
      try {
        providerProfile = await supabase
            .from('provider_profiles').select()
            .eq('provider_id', userId).single();
      } catch (_) {}
      
      // Load subscription for providers
      try {
        final sub = await supabase
            .from('subscriptions')
            .select()
            .eq('provider_id', userId)
            .maybeSingle();
        subscription = sub;
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _verification = verification;
        _providerProfile = providerProfile;
        _subscription = subscription;
        _isAdmin = isAdmin;
        _loading = false;
      });
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final name       = _profile?['full_name'] ?? 'User';
    final userType   = _profile?['user_type'] ?? 'client';
    final isProvider = userType == 'provider';
    final isVerified = _profile?['is_verified'] == true;
    final vStatus    = _verification?['status'];
    
    // Check if subscription is active
    final bool hasActiveSubscription = _subscription != null && 
        _subscription!['status'] == 'active';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beauty Home Services'),
        actions: [
          if (_isAdmin)
            IconButton(
              icon: const Icon(Icons.admin_panel_settings),
              tooltip: 'Admin Panel',
              onPressed: () => context.go('/admin/verify'),
            ),
          IconButton(icon: const Icon(Icons.logout), onPressed: _signOut),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Welcome card
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: TextStyle(
                          fontSize: 24,
                          color: Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Welcome back,',
                              style: Theme.of(context).textTheme.bodySmall),
                          Text(name,
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Row(children: [
                            _Badge(
                              label: isProvider ? '✂️ Provider' : '💅 Client',
                              color: isProvider ? Colors.purple.shade100 : Colors.pink.shade100,
                              textColor: isProvider ? Colors.purple.shade800 : Colors.pink.shade800,
                            ),
                            const SizedBox(width: 8),
                            _Badge(
                              label: isVerified ? '✅ Verified' : '⏳ Unverified',
                              color: isVerified ? Colors.green.shade100 : Colors.orange.shade100,
                              textColor: isVerified ? Colors.green.shade800 : Colors.orange.shade800,
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Verification banner
            if (!isVerified) ...[
              _VerificationBanner(
                status: vStatus,
                onTap: () {
                  if (vStatus == null || vStatus == 'rejected') {
                    context.go('/verify');
                  } else {
                    context.go('/verify/pending');
                  }
                },
              ),
              const SizedBox(height: 20),
            ],

            // Provider dashboard
            if (isProvider && isVerified) ...[
              Text('Provider Dashboard',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // Availability status
              if (_providerProfile != null)
                _AvailabilityCard(
                  status: _providerProfile!['availability_status'],
                  onChanged: (newStatus) async {
                    await supabase
                        .from('provider_profiles')
                        .update({'availability_status': newStatus})
                        .eq('provider_id', supabase.auth.currentUser!.id);
                    setState(() =>
                        _providerProfile!['availability_status'] = newStatus);
                  },
                ),

              const SizedBox(height: 12),

              // Subscription warning banner
              if (!hasActiveSubscription)
                GestureDetector(
                  onTap: () => context.go('/provider/subscription'),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: const Row(children: [
                      Icon(Icons.workspace_premium_rounded, color: Colors.red),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'No active subscription — your profile is hidden from clients.',
                          style: TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                      Icon(Icons.chevron_right, color: Colors.red),
                    ]),
                  ),
                ),

              // Dashboard tiles
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
                childAspectRatio: 1.3,
                children: [
                  _DashTile(
                    icon: Icons.person_outline,
                    label: 'Edit Profile',
                    color: Colors.blue,
                    onTap: () => context.go('/provider/profile/edit'),
                  ),
                  _DashTile(
                    icon: Icons.content_cut_rounded,
                    label: 'My Services',
                    color: Colors.purple,
                    onTap: () => context.go('/provider/services'),
                  ),
                  _DashTile(
                    icon: Icons.photo_library_outlined,
                    label: 'Gallery',
                    color: Colors.pink,
                    onTap: () => context.go('/provider/gallery'),
                  ),
                  _DashTile(
                    icon: Icons.public_outlined,
                    label: 'My Public Profile',
                    color: Colors.teal,
                    onTap: () => context.go('/provider/${supabase.auth.currentUser!.id}'),
                  ),
                  _DashTile(
                    icon: Icons.workspace_premium_rounded,
                    label: 'Subscription',
                    color: Colors.green,
                    onTap: () => context.go('/provider/subscription'),
                  ),
                  _DashTile(
                    icon: Icons.calendar_month_rounded,
                    label: 'Bookings',
                    color: Colors.orange,
                    onTap: () => context.go('/provider/bookings'),
                  ),
                  _DashTile(
                    icon: Icons.account_balance_wallet_rounded,
                    label: 'My Earnings',
                    color: Colors.green,
                    onTap: () => context.go('/earnings'),
                  ),
                ],
              ),
            ],

            // Provider not yet set up
            if (isProvider && isVerified && _providerProfile == null) ...[
              const SizedBox(height: 12),
              Card(
                color: Colors.blue.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text('Complete your provider profile to appear in search results.',
                          textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () {
                          context.go('/provider/profile/edit');
                        },
                        child: const Text('Set Up Profile'),
                      ),
                    ],
                  ),
                ),
              ),
            ],

            // Client home
            if (!isProvider && isVerified) ...[
              Text('Find a Stylist',
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              _DashTile(
                icon: Icons.search_rounded,
                label: 'Browse Stylists',
                color: Colors.blue,
                onTap: () => context.go('/browse'),
              ),
              const SizedBox(height: 8),
              _DashTile(
                icon: Icons.calendar_today_outlined,
                label: 'My Bookings',
                color: Colors.pink,
                onTap: () => context.go('/client/bookings'),
              ),
              const SizedBox(height: 8),
              _DashTile(
                icon: Icons.favorite_rounded,
                label: 'Favourite Stylists',
                color: Colors.red,
                onTap: () => context.go('/favorites'),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.blue),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Browse available stylists and tap "Book Now" to schedule an appointment.',
                        style: TextStyle(fontSize: 12, color: Colors.blue),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  const _AvailabilityCard({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case 'available':
        color = Colors.green; label = '🟢 Available'; break;
      case 'busy':
        color = Colors.orange; label = '🟠 Busy'; break;
      default:
        color = Colors.grey; label = '⚫ Offline';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Text(label,
                style: TextStyle(
                    fontWeight: FontWeight.bold, color: color, fontSize: 15)),
            const Spacer(),
            PopupMenuButton<String>(
              onSelected: onChanged,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'available', child: Text('🟢 Available')),
                PopupMenuItem(value: 'busy',      child: Text('🟠 Busy')),
                PopupMenuItem(value: 'offline',   child: Text('⚫ Offline')),
              ],
              child: const Chip(label: Text('Change')),
            ),
          ],
        ),
      ),
    );
  }
}

class _DashTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DashTile({required this.icon, required this.label,
      required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(label,
                style: TextStyle(
                    color: color, fontWeight: FontWeight.w600, fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final String? status;
  final VoidCallback onTap;
  const _VerificationBanner({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color bg; String message; IconData icon;
    switch (status) {
      case 'pending':
        bg = Colors.orange.shade50;
        message = 'Your verification is under review. Tap to see status.';
        icon = Icons.hourglass_top_rounded; break;
      case 'rejected':
        bg = Colors.red.shade50;
        message = 'Verification rejected. Tap to re-submit your documents.';
        icon = Icons.cancel_outlined; break;
      default:
        bg = Colors.blue.shade50;
        message = 'Verify your identity to unlock all features. Tap to start.';
        icon = Icons.verified_user_outlined;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          Icon(icon, color: Colors.grey.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text(message, style: const TextStyle(fontSize: 13))),
          const Icon(Icons.chevron_right, color: Colors.grey),
        ]),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label; final Color color; final Color textColor;
  const _Badge({required this.label, required this.color, required this.textColor});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(label, style: TextStyle(fontSize: 12, color: textColor)),
    );
  }
}