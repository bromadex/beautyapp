import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../utils/feel.dart';

class ProviderProfileHubScreen extends StatefulWidget {
  const ProviderProfileHubScreen({super.key});
  @override
  State<ProviderProfileHubScreen> createState() => _ProviderProfileHubScreenState();
}

class _ProviderProfileHubScreenState extends State<ProviderProfileHubScreen> {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;
  Map<String, dynamic>? _pp;
  int _services = 0;
  int _photos = 0;
  int _publicOffers = 0;
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
    try {
      Future<dynamic> safe(Future<dynamic> f) => f.then<dynamic>((v) => v, onError: (_) => null);
      final r = await Future.wait<dynamic>([
        safe(supabase.from('provider_profiles').select().eq('provider_id', userId).maybeSingle()),
        safe(supabase.from('services').select('id').eq('provider_id', userId).eq('is_active', true)),
        safe(supabase.from('hairstyle_gallery').select('id').eq('provider_id', userId).limit(12)),
        safe(supabase.from('promotions').select('id').eq('provider_id', userId).eq('is_public', true).eq('is_active', true)),
      ]);
      _pp = r[0] as Map<String, dynamic>?;
      _services = (r[1] as List?)?.length ?? 0;
      _photos = (r[2] as List?)?.length ?? 0;
      _publicOffers = (r[3] as List?)?.length ?? 0;
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
              _MeCard(
                name: name,
                avatar: _profile?['avatar_url'] as String?,
                line: [
                  if ((_pp?['title'] ?? '').toString().trim().isNotEmpty) _pp!['title'],
                  if ((_pp?['area'] ?? '').toString().trim().isNotEmpty) _pp!['area'],
                ].join(' · '),
                rating: (_pp?['average_rating'] as num?)?.toDouble() ?? 0,
                reviews: (_pp?['total_reviews'] as num?)?.toInt() ?? 0,
                verified: _profile?['is_verified'] == true,
                plan: hasActiveSub ? 'Pro plan' : 'Free plan',
                email: email,
                onView: () => context.push('/provider/$uid'),
              ),
              const SizedBox(height: 12),
              _Checklist(items: [
                (done: (_profile?['avatar_url'] ?? '').toString().isNotEmpty, label: 'Profile photo',
                    onTap: () => context.push('/provider/profile/edit').then((_) => _load())),
                (done: _services >= 3, label: _services >= 3 ? '$_services services with prices' : 'At least 3 services ($_services so far)',
                    onTap: () => context.push('/provider/services').then((_) => _load())),
                (done: (_pp?['whatsapp_number'] ?? '').toString().trim().isNotEmpty &&
                        ['whatsapp', 'both'].contains(_pp?['preferred_contact']),
                    label: 'WhatsApp contact on',
                    onTap: () => context.push('/provider/settings').then((_) => _load())),
                (done: _photos >= 6, label: _photos >= 6 ? '6+ work photos' : '6 work photos ($_photos so far)',
                    onTap: () => context.push('/provider/gallery').then((_) => _load())),
              ]),
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
                    icon: TablerIcons.calendar_repeat,
                    iconColor: IosColors.gold,
                    title: 'Monthly packages',
                    subtitle: 'Regular visits for one monthly price',
                    onTap: () => context.push('/provider/packages'),
                  ),
                  IosRow(
                    icon: TablerIcons.sparkles,
                    iconColor: IosColors.orange,
                    title: 'Tips & trends',
                    subtitle: _profile?['is_verified'] == true
                        ? 'Share aftercare and how-tos with clients'
                        : 'Read tips. Verified pros can write them',
                    onTap: () => context.push('/tips'),
                  ),
                  IosRow(
                    icon: TablerIcons.tag,
                    iconColor: IosColors.purple,
                    title: 'Promotions',
                    subtitle: _publicOffers > 0
                        ? '$_publicOffers shown publicly · discounts and codes'
                        : 'Create discounts and offers',
                    onTap: () => context.push('/provider/promotions').then((_) => _load()),
                  ),
                  IosRow(
                    icon: TablerIcons.shopping_bag,
                    iconColor: IosColors.teal,
                    title: 'My shop',
                    subtitle: 'Sell products. Buyers order and pay you directly',
                    onTap: () => context.push('/provider/shop'),
                  ),
                  IosRow(
                    icon: TablerIcons.building_store,
                    iconColor: IosColors.orange,
                    title: 'Shop',
                    subtitle: 'Browse and buy from other pros',
                    onTap: () => context.push('/market'),
                  ),
                  IosRow(
                    icon: TablerIcons.receipt,
                    iconColor: IosColors.gray,
                    title: 'Orders',
                    subtitle: 'What you\'ve bought and sold',
                    onTap: () => context.push('/orders'),
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

class _MeCard extends StatelessWidget {
  final String name;
  final String? avatar;
  final String line;
  final double rating;
  final int reviews;
  final bool verified;
  final String plan;
  final String email;
  final VoidCallback onView;
  const _MeCard({
    required this.name,
    required this.avatar,
    required this.line,
    required this.rating,
    required this.reviews,
    required this.verified,
    required this.plan,
    required this.email,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final dark = AppColors.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF1E1912) : const Color(0xFF141210),
        borderRadius: BorderRadius.circular(26),
        border: dark ? Border.all(color: const Color(0xFF2F2A22)) : null,
      ),
      child: Row(children: [
        SizedBox(width: 64, height: 64, child: ProPhoto(name: name, url: avatar, radius: 20)),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFFF7F3EC))),
            if (line.isNotEmpty)
              Text(line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12.5, color: Color(0xFFBDB3A4))),
            const SizedBox(height: 3),
            Text(
                [
                  reviews > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New',
                  if (verified) 'Verified',
                  plan,
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: Color(0xFFE2BE7A), fontWeight: FontWeight.w600)),
            if (email.isNotEmpty)
              Text(email,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF8F877B))),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: onView,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.gold,
            foregroundColor: const Color(0xFF17130E),
            minimumSize: const Size(0, 36),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: const StadiumBorder(),
            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          child: const Text('View profile'),
        ),
      ]),
    );
  }
}

/// "Profile 75% complete" with what's left to do.
class _Checklist extends StatelessWidget {
  final List<({bool done, String label, VoidCallback onTap})> items;
  const _Checklist({required this.items});

  @override
  Widget build(BuildContext context) {
    final done = items.where((i) => i.done).length;
    if (done == items.length) return const SizedBox.shrink();
    final pct = (done / items.length * 100).round();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.isDark ? null : AppShadows.lifted,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Profile $pct% complete',
            style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: done / items.length),
              duration: Motion.of(context, Motion.slow),
              builder: (_, v, _) => LinearProgressIndicator(
                value: v,
                minHeight: 8,
                backgroundColor: AppColors.surfaceMuted,
                color: AppColors.gold,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        for (final i in items)
          InkWell(
            onTap: i.done ? null : i.onTap,
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              height: 38,
              child: Row(children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i.done ? AppColors.gold : null,
                    border: i.done ? null : Border.all(color: AppColors.borderStrong, width: 2),
                  ),
                  child: i.done ? const Icon(TablerIcons.check, size: 12, color: Color(0xFF17130E)) : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(i.label,
                      style: TextStyle(
                          fontSize: 13.5,
                          color: i.done ? AppColors.textSecondary : AppColors.textPrimary,
                          decoration: i.done ? TextDecoration.lineThrough : null)),
                ),
                if (!i.done)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text('Do it',
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.goldText)),
                  ),
              ]),
            ),
          ),
      ]),
    );
  }
}
