import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';
import '../theme.dart';
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
              .select('provider_id, title, average_rating, total_reviews, is_hidden')
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
      if (mounted) {
        setState(() {
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
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final s = _salon;
    if (s == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: TablerIcons.building_store, title: 'Salon not found', message: 'It may have closed.'),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(s['name'] ?? 'Salon')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.xlAll),
          child: Row(children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(color: AppColors.primaryDark, borderRadius: AppRadius.mdAll),
              child: const Icon(TablerIcons.building_store, color: AppColors.gold, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s['name'] ?? '', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
                if ((s['address'] ?? '').toString().isNotEmpty)
                  Text(s['address'], style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
                const SizedBox(height: 4),
                Text('${_team.length} beauty ${_team.length == 1 ? 'pro' : 'pros'}',
                    style: const TextStyle(color: AppColors.goldLight, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Choose who to book', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final m in _team)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              leading: PersonAvatar(name: m['full_name'] ?? '', url: m['avatar_url'], size: 48),
              title: Row(children: [
                Flexible(child: Text(m['full_name'] ?? 'Beauty pro', style: const TextStyle(fontWeight: FontWeight.w800))),
                if (m['is_verified'] == true) ...[
                  const SizedBox(width: 4),
                  const Icon(TablerIcons.rosette_discount_check_filled, size: 16, color: AppColors.primary),
                ],
              ]),
              subtitle: Text([
                (m['title'] ?? '').toString().isNotEmpty ? m['title'] : (m['role'] == 'owner' ? 'Owner' : 'Beauty pro'),
                if (((m['total_reviews'] as num?) ?? 0) > 0)
                  '★ ${((m['average_rating'] as num?) ?? 0).toStringAsFixed(1)} (${m['total_reviews']})',
              ].join(' · ')),
              trailing: const Icon(TablerIcons.chevron_right),
              onTap: () => context.push('/provider/${m['id']}'),
            ),
          ),
      ]),
    );
  }
}
