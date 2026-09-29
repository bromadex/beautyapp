import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Admin: reported reviews to hide or keep, and cities clients are asking for.
class AdminModerationScreen extends StatefulWidget {
  final int initialTab;
  const AdminModerationScreen({super.key, this.initialTab = 0});

  @override
  State<AdminModerationScreen> createState() => _AdminModerationScreenState();
}

class _AdminModerationScreenState extends State<AdminModerationScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _reported = [];
  List<Map<String, dynamic>> _demand = [];
  List<Map<String, dynamic>> _flagged = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait<dynamic>([
        supabase
            .from('review_reports')
            .select('reason, created_at, review_id, reviews(id, rating, comment, after_service_image_url, created_at, '
                'client:profiles!reviews_client_id_fkey(full_name), provider:profiles!reviews_provider_id_fkey(full_name))')
            .eq('status', 'open')
            .order('created_at'),
        supabase.rpc('area_demand', params: {'p_days': 90}),
        supabase
            .from('services')
            .select('id, service_name, description, flag_reason, price, provider_id, service_categories(name)')
            .eq('review_status', 'flagged')
            .order('created_at'),
      ]);
      final flagged = List<Map<String, dynamic>>.from(results[2] as List);
      final ids = flagged.map((f) => f['provider_id']).toSet().toList();
      if (ids.isNotEmpty) {
        final names = await supabase.from('profiles').select('id, full_name').inFilter('id', ids);
        final byId = {for (final n in names) n['id']: n['full_name']};
        for (final f in flagged) {
          f['pro_name'] = byId[f['provider_id']];
        }
      }
      // One card per review, listing every reason it was reported for.
      final byReview = <String, Map<String, dynamic>>{};
      for (final r in List<Map<String, dynamic>>.from(results[0] as List)) {
        final review = r['reviews'] as Map<String, dynamic>?;
        if (review == null) continue;
        final entry = byReview.putIfAbsent(r['review_id'], () => {'review': review, 'reasons': <String>[]});
        (entry['reasons'] as List<String>).add(r['reason']);
      }
      if (mounted) {
        setState(() {
          _reported = byReview.values.toList();
          _demand = List<Map<String, dynamic>>.from(results[1] as List);
          _flagged = flagged;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load: $e')));
      }
    }
  }

  Future<void> _decide(String reviewId, bool hide) async {
    try {
      await supabase.rpc('moderate_review', params: {'p_review': reviewId, 'p_hide': hide});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(hide ? 'Review hidden. The rating has been updated.' : 'Review kept')));
      }
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  String _ago(String iso) {
    final d = DateTime.now().difference(DateTime.parse(iso).toLocal());
    if (d.inDays > 0) return '${d.inDays}d ago';
    if (d.inHours > 0) return '${d.inHours}h ago';
    return '${d.inMinutes}m ago';
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab.clamp(0, 2),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Reviews & Demand'),
          bottom: TabBar(tabs: [
            Tab(text: 'Reported (${_reported.length})'),
            Tab(text: 'Flagged (${_flagged.length})'),
            const Tab(text: 'Area requests'),
          ]),
        ),
        body: _loading
            ? const LoadingPlaceholder()
            : TabBarView(children: [
                RefreshIndicator(onRefresh: _load, child: _buildReported()),
                RefreshIndicator(onRefresh: _load, child: _buildFlagged()),
                RefreshIndicator(onRefresh: _load, child: _buildDemand()),
              ]),
      ),
    );
  }

  Widget _buildReported() {
    if (_reported.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
          icon: TablerIcons.shield_check,
          title: 'Nothing to review',
          message: 'Reviews that clients or beauty pros report will appear here.',
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _reported.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final item = _reported[i];
        final r = item['review'] as Map<String, dynamic>;
        final reasons = item['reasons'] as List<String>;
        final rating = (r['rating'] as num?)?.toInt() ?? 0;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${r['client']?['full_name'] ?? 'Client'} → ${r['provider']?['full_name'] ?? 'Pro'}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text('★' * rating + '☆' * (5 - rating), style: TextStyle(color: AppColors.warning)),
            ]),
            const SizedBox(height: 6),
            Text((r['comment'] ?? '').toString().isEmpty ? '(no comment)' : r['comment'],
                style: const TextStyle(fontSize: 14, height: 1.4)),
            if (r['after_service_image_url'] != null) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: AppRadius.smAll,
                child: Image.network(r['after_service_image_url'], height: 120, fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const SizedBox.shrink()),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final reason in reasons.toSet())
                Pill(label: '$reason${reasons.where((x) => x == reason).length > 1 ? ' ×${reasons.where((x) => x == reason).length}' : ''}',
                    color: AppColors.error),
            ]),
            const SizedBox(height: 4),
            Text('Posted ${_ago(r['created_at'])}',
                style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: OutlinedButton(onPressed: () => _decide(r['id'], false), child: const Text('Keep')),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _decide(r['id'], true),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: const Text('Hide review'),
                ),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Future<void> _reviewService(String id, bool approve) async {
    try {
      await supabase.rpc('review_service', params: {'p_service': id, 'p_approve': approve});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(approve ? 'Service approved' : 'Service removed. The pro has been told why.')));
      }
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Widget _buildFlagged() {
    if (_flagged.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
          icon: TablerIcons.shield_check,
          title: 'Nothing flagged',
          message: 'Services that mention medical treatments (fillers, injections, lasers) wait here for your decision.',
        ),
      ]);
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: _flagged.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (_, i) {
        final f = _flagged[i];
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(f['service_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            Text('${f['pro_name'] ?? 'Pro'} · ${f['service_categories']?['name'] ?? ''} · \$${f['price']}',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            if ((f['description'] ?? '').toString().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(f['description'], style: const TextStyle(fontSize: 14, height: 1.4)),
            ],
            const SizedBox(height: 8),
            Pill(label: f['flag_reason'] ?? 'Flagged', color: AppColors.warningText),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: () => _reviewService(f['id'], true), child: const Text('Allow'))),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton(
                  onPressed: () => _reviewService(f['id'], false),
                  style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                  child: const Text('Remove'),
                ),
              ),
            ]),
          ]),
        );
      },
    );
  }

  Widget _buildDemand() {
    if (_demand.isEmpty) {
      return ListView(children: const [
        SizedBox(height: 80),
        EmptyState(
          icon: TablerIcons.map,
          title: 'No requests yet',
          message: 'When clients can\'t find a beauty pro nearby they can ask for their area. Requests from the last 90 days show here.',
        ),
      ]);
    }
    final top = (_demand.first['requests'] as num).toDouble();
    return ListView(padding: const EdgeInsets.all(16), children: [
      Text('Where clients want BeauTap next (last 90 days). Recruit beauty pros here first.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 12),
      for (final d in _demand)
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: AppColors.border),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(d['city'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
              Text('${d['requests']}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: AppRadius.smAll,
              child: LinearProgressIndicator(
                value: (d['requests'] as num) / top,
                minHeight: 6,
                backgroundColor: AppColors.surfaceMuted,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              [
                '${d['people']} signed-in ${d['people'] == 1 ? 'person' : 'people'}',
                if (d['top_category'] != null) 'mostly ${d['top_category']}',
                'last ${_ago(d['last_at'])}',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
            ),
          ]),
        ),
    ]);
  }
}
