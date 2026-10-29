import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/nav.dart';
import '../utils/pro_photos.dart';
import '../widgets/ui.dart';

/// Public salon page: the salon and everyone who works there.
class SalonPublicScreen extends StatefulWidget {
  final String salonId;
  const SalonPublicScreen({super.key, required this.salonId});

  @override
  State<SalonPublicScreen> createState() => _SalonPublicScreenState();
}

class _SalonPublicScreenState extends State<SalonPublicScreen> {
  Map<String, dynamic>? _salon;
  List<Map<String, dynamic>> _team = [];
  Map<String, String> _covers = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final salon = await supabase
          .from('salons')
          .select('id, owner_id, name, address')
          .eq('id', widget.salonId)
          .maybeSingle();
      final members = await supabase
          .from('salon_members')
          .select('role, joined_at, profiles!salon_members_provider_id_fkey(id, full_name, avatar_url, is_verified)')
          .eq('salon_id', widget.salonId)
          .order('joined_at');
      final ids = [for (final m in members as List) (m['profiles'] as Map?)?['id']].whereType<String>().toList();
      final pps = ids.isEmpty
          ? const []
          : await supabase
              .from('provider_profiles')
              .select('provider_id, title, area, average_rating, total_reviews, is_hidden')
              .inFilter('provider_id', ids);
      final byId = {for (final p in pps) p['provider_id']: p};
      final team = <Map<String, dynamic>>[];
      for (final m in members) {
        final p = m['profiles'] as Map?;
        if (p == null) continue;
        final pp = byId[p['id']] as Map?;
        if (pp?['is_hidden'] == true) continue;
        team.add({...Map<String, dynamic>.from(p), 'role': m['role'], ...?pp?.cast<String, dynamic>()});
      }
      team.sort((a, b) => (a['role'] == 'owner' ? 0 : 1).compareTo(b['role'] == 'owner' ? 0 : 1));
      final covers = await loadCoverPhotos();
      if (mounted) {
        setState(() {
          _covers = covers;
          _salon = salon;
          _team = team;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingPlaceholder(kind: PlaceholderKind.detail));
    final s = _salon;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: TablerIcons.building_store, title: 'Salon not found', message: 'It may have closed.'),
      );
    }
    // Header photo: the newest work photo from anyone on the team.
    final header = _team.map((m) => _covers[m['id']]).whereType<String>().firstOrNull;
    final rated = _team.where((m) => ((m['total_reviews'] as num?) ?? 0) > 0).toList();
    final avg = rated.isEmpty
        ? null
        : rated.map((m) => (m['average_rating'] as num).toDouble()).reduce((a, b) => a + b) / rated.length;
    final area = _team.map((m) => (m['area'] ?? '').toString()).firstWhere((a) => a.isNotEmpty, orElse: () => '');
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: 250,
            child: Stack(fit: StackFit.expand, children: [
              header != null
                  ? Image.network(header, fit: BoxFit.cover, cacheWidth: 1000,
                      errorBuilder: (_, _, _) => Image.asset('assets/photos/welcome_2.jpg', fit: BoxFit.cover))
                  : Image.asset('assets/photos/welcome_2.jpg', fit: BoxFit.cover),
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x4D000000), Color(0x00000000), Color(0xD90B0A09)],
                    stops: [0, 0.4, 1],
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Material(
                      color: const Color(0xEBFFFFFF),
                      shape: const CircleBorder(),
                      child: IconButton(
                        tooltip: 'Back',
                        icon: const Icon(TablerIcons.chevron_left, color: Color(0xFF17130E)),
                        onPressed: () => goBack(context),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 20,
                right: 20,
                bottom: 18,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['name'] ?? '',
                      style: const TextStyle(
                          fontFamily: 'InterDisplay',
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (area.isNotEmpty) area,
                      '${_team.length} beauty ${_team.length == 1 ? 'pro' : 'pros'}',
                      if (avg != null) '★ ${avg.toStringAsFixed(1)}',
                    ].join(' · '),
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFFE7DCC8)),
                  ),
                ]),
              ),
            ]),
          ),
        ),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(16, 18, 16, 32 + MediaQuery.paddingOf(context).bottom),
          sliver: SliverList.list(children: [
            Text('The team', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 4),
            Text('Choose who to book.', style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            const SizedBox(height: 12),
            AdaptiveGrid(
              minTileWidth: 150,
              gap: 10,
              children: [for (final m in _team) _TeamCard(member: m, photo: coverFor(_covers, m['id'], m['avatar_url']))],
            ),
          ]),
        ),
      ]),
    );
  }
}

class _TeamCard extends StatelessWidget {
  final Map<String, dynamic> member;
  final String? photo;
  const _TeamCard({required this.member, required this.photo});

  @override
  Widget build(BuildContext context) {
    final m = member;
    final name = (m['full_name'] ?? 'Beauty pro').toString();
    final reviews = (m['total_reviews'] as num?)?.toInt() ?? 0;
    final title = (m['title'] ?? '').toString().isNotEmpty ? m['title'] : (m['role'] == 'owner' ? 'Owner' : 'Beauty pro');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/provider/${m['id']}'),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(
                height: 136,
                width: double.infinity,
                child: Stack(fit: StackFit.expand, children: [
                  ProPhoto(name: name, url: photo, radius: 16),
                  Positioned(
                    left: 6,
                    bottom: 6,
                    child: PhotoBadge(
                        text: reviews > 0 ? '★ ${((m['average_rating'] as num?) ?? 0).toStringAsFixed(1)}' : 'New'),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                child: Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  ),
                  if (m['is_verified'] == true) ...[
                    const SizedBox(width: 3),
                    Icon(TablerIcons.rosette_discount_check_filled, size: 15, color: AppColors.info),
                  ],
                ]),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                child: Text('$title', maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
