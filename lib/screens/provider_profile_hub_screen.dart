import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

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
        body: const LoadingPlaceholder(kind: PlaceholderKind.profile),
      );
    }

    final name = _profile?['full_name'] ?? 'Provider';
    final email = supabase.auth.currentUser?.email ?? '';
    final uid = supabase.auth.currentUser!.id;
    final hasActiveSub = _subscription != null && _subscription!['status'] == 'active';

    return Scaffold(
      appBar: largeTitleBar(context, 'Me'),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 4 + tabBarSpace(context)),
        children: [
          PageWidth(
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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

              // Two columns of sections on wide screens, one on phones.
              AdaptiveColumns(children: [
              IosSection(header: 'Money and bookings', children: [
                  IosRow(
                    icon: TablerIcons.wallet,
                    iconColor: IosColors.green,
                    title: 'Earnings',
                    subtitle: 'What you\'ve made, by week and month',
                    onTap: () => context.push('/earnings'),
                  ),
                  IosRow(
                    icon: TablerIcons.list,
                    iconColor: IosColors.blue,
                    title: 'All bookings',
                    subtitle: 'Requests, upcoming and past bookings',
                    onTap: () => context.push('/provider/bookings'),
                  ),
              ]),
              IosSection(header: 'Your profile', children: [
                  IosRow(
                    icon: TablerIcons.user,
                    iconColor: IosColors.gray,
                    title: 'Edit Profile',
                    subtitle: 'Bio, location, service radius',
                    onTap: () => context.push('/provider/profile/edit'),
                  ),
                  IosRow(
                    icon: TablerIcons.scissors,
                    iconColor: IosColors.forest,
                    title: 'My Services',
                    subtitle: 'Manage what you offer and pricing',
                    onTap: () => context.push('/provider/services'),
                  ),
                  IosRow(
                    icon: TablerIcons.photo,
                    iconColor: IosColors.pink,
                    title: 'Gallery',
                    subtitle: 'Showcase your work',
                    onTap: () => context.push('/provider/gallery'),
                  ),
                  IosRow(
                    icon: TablerIcons.clock,
                    iconColor: IosColors.orange,
                    title: 'Working Hours',
                    subtitle: 'Set your schedule and blocked dates',
                    onTap: () => context.push('/provider/availability'),
                  ),
                  IosRow(
                    icon: TablerIcons.map_pin,
                    iconColor: IosColors.red,
                    title: 'Where you work',
                    subtitle: 'Your city and area. Change it if you move',
                    onTap: () => context.push('/provider/location'),
                  ),
              ]),
              IosSection(header: 'Grow your business', children: [
                  IosRow(
                    icon: TablerIcons.crown,
                    iconColor: IosColors.forest,
                    title: 'Subscription',
                    subtitle: hasActiveSub ? 'Manage your plan' : 'Subscribe to appear in search',
                    onTap: () => context.push('/provider/subscription'),
                  ),
                  IosRow(
                    icon: TablerIcons.tag,
                    iconColor: IosColors.purple,
                    title: 'Promotions',
                    subtitle: 'Create discounts and offers',
                    onTap: () => context.push('/provider/promotions'),
                  ),
                  IosRow(
                    icon: TablerIcons.shopping_bag,
                    iconColor: IosColors.teal,
                    title: 'Products',
                    subtitle: 'Advertise what you sell. 3 free',
                    onTap: () => context.push('/provider/products'),
                  ),
                  IosRow(
                    icon: TablerIcons.building_store,
                    iconColor: IosColors.indigo,
                    title: 'Salon',
                    subtitle: 'Create or join a salon. One plan for up to 8',
                    onTap: () => context.push('/provider/salon'),
                  ),
                  IosRow(
                    icon: TablerIcons.gift,
                    iconColor: IosColors.gold,
                    title: 'Invite pros',
                    subtitle: 'Invite 2 pros, get 2 months free',
                    onTap: () => context.push('/provider/referrals'),
                  ),
              ]),
              IosSection(header: 'Clients', children: [
                  IosRow(
                    icon: TablerIcons.star,
                    iconColor: IosColors.yellow,
                    title: 'My Reviews',
                    subtitle: 'See what clients say about you',
                    onTap: () => context.push('/provider/$uid/reviews'),
                  ),
                  IosRow(
                    icon: TablerIcons.eye,
                    iconColor: IosColors.blue,
                    title: 'Public Profile',
                    subtitle: 'View your profile as clients see it',
                    onTap: () => context.push('/provider/$uid'),
                  ),
                  IosRow(
                    icon: TablerIcons.file_invoice,
                    iconColor: IosColors.teal,
                    title: 'Service Requests',
                    subtitle: 'Browse and quote on client requests',
                    onTap: () => context.push('/provider/service-requests'),
                  ),
              ]),
              IosSection(children: [
                  IosRow(
                    icon: TablerIcons.adjustments_horizontal,
                    iconColor: IosColors.gray,
                    title: 'Business Settings',
                    subtitle: 'Travel fees, cancellation, buffer time',
                    onTap: () => context.push('/provider/settings'),
                  ),
                  IosRow(
                    icon: TablerIcons.settings,
                    iconColor: IosColors.gray,
                    title: 'Account Settings',
                    subtitle: 'Deactivate or delete your account',
                    onTap: () => context.push('/account/settings'),
                  ),
              ]),
              IosSection(children: [
                IosRow(title: 'Sign Out', destructive: true, onTap: _signOut),
              ]),
              ]),
              const SizedBox(height: AppSpacing.xxxl),
            ]),
          ),
        ],
      ),
    );
  }
}
