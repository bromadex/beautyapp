import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ProviderProfileHubScreen extends StatefulWidget {
  const ProviderProfileHubScreen({super.key});
  @override
  State<ProviderProfileHubScreen> createState() => _ProviderProfileHubScreenState();
}

class _ProviderProfileHubScreenState extends State<ProviderProfileHubScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }
    Map<String, dynamic> profile;
    try {
      profile = await supabase.from('profiles').select().eq('id', userId).single();
    } catch (_) {
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
      return;
    }
    Map<String, dynamic>? subscription;
    try {
      subscription = await supabase
          .from('subscriptions').select()
          .eq('provider_id', userId)
          .maybeSingle();
    } catch (_) {}
    if (mounted) {
      setState(() {
        _profile = profile;
        _subscription = subscription;
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
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final name = _profile?['full_name'] ?? 'Provider';
    final email = supabase.auth.currentUser?.email ?? '';
    final uid = supabase.auth.currentUser!.id;
    final hasActiveSub = _subscription != null && _subscription!['status'] == 'active';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Me'),
        automaticallyImplyLeading: false,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: ListView(
            padding: AppSpacing.screenPadding,
            children: [
              // Profile header
              Container(
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  borderRadius: AppRadius.lgAll,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 60, height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white38, width: 2),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        name.isNotEmpty ? name[0].toUpperCase() : '?',
                        style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                          if (email.isNotEmpty)
                            Text(email, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: hasActiveSub
                                  ? AppColors.success.withValues(alpha: 0.3)
                                  : Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              hasActiveSub ? 'Subscribed' : 'No subscription',
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xl),

              _HubTile(
                icon: TablerIcons.wallet,
                label: 'Earnings',
                subtitle: 'What you\'ve made, by week and month',
                onTap: () => context.push('/earnings'),
              ),
              _HubTile(
                icon: TablerIcons.list,
                label: 'All bookings',
                subtitle: 'Requests, upcoming and past bookings',
                onTap: () => context.push('/provider/bookings'),
              ),
              _HubTile(
                icon: TablerIcons.user,
                label: 'Edit Profile',
                subtitle: 'Bio, location, service radius',
                onTap: () => context.push('/provider/profile/edit'),
              ),
              _HubTile(
                icon: TablerIcons.scissors,
                label: 'My Services',
                subtitle: 'Manage what you offer and pricing',
                onTap: () => context.push('/provider/services'),
              ),
              _HubTile(
                icon: TablerIcons.photo,
                label: 'Gallery',
                subtitle: 'Showcase your work',
                onTap: () => context.push('/provider/gallery'),
              ),
              _HubTile(
                icon: TablerIcons.clock,
                label: 'Working Hours',
                subtitle: 'Set your schedule and blocked dates',
                onTap: () => context.push('/provider/availability'),
              ),
              _HubTile(
                icon: TablerIcons.tag,
                label: 'Promotions',
                subtitle: 'Create discounts and offers',
                onTap: () => context.push('/provider/promotions'),
              ),
              _HubTile(
                icon: TablerIcons.crown,
                label: 'Subscription',
                subtitle: hasActiveSub ? 'Manage your plan' : 'Subscribe to appear in search',
                onTap: () => context.push('/provider/subscription'),
              ),
              _HubTile(
                icon: TablerIcons.star,
                label: 'My Reviews',
                subtitle: 'See what clients say about you',
                onTap: () => context.push('/provider/$uid/reviews'),
              ),
              _HubTile(
                icon: TablerIcons.eye,
                label: 'Public Profile',
                subtitle: 'View your profile as clients see it',
                onTap: () => context.push('/provider/$uid'),
              ),
              _HubTile(
                icon: TablerIcons.adjustments_horizontal,
                label: 'Business Settings',
                subtitle: 'Travel fees, cancellation, buffer time',
                onTap: () => context.push('/provider/settings'),
              ),
              _HubTile(
                icon: TablerIcons.file_invoice,
                label: 'Service Requests',
                subtitle: 'Browse and quote on client requests',
                onTap: () => context.push('/provider/service-requests'),
              ),
              _HubTile(
                icon: TablerIcons.settings,
                label: 'Account Settings',
                subtitle: 'Deactivate or delete your account',
                onTap: () => context.push('/account/settings'),
              ),
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton.icon(
                onPressed: _signOut,
                icon: const Icon(TablerIcons.logout, size: 18),
                label: const Text('Sign Out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.error,
                  side: BorderSide(color: AppColors.error.withValues(alpha: 0.4)),
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                ),
              ),
              const SizedBox(height: AppSpacing.xxxl),
            ],
          ),
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;
  const _HubTile({required this.icon, required this.label, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                ),
              ),
              Icon(TablerIcons.chevron_right, color: AppColors.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}
