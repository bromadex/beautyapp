import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class AdminDisputesScreen extends StatefulWidget {
  const AdminDisputesScreen({super.key});

  @override
  State<AdminDisputesScreen> createState() => _AdminDisputesScreenState();
}

class _AdminDisputesScreenState extends State<AdminDisputesScreen> {
  static const _filters = {
    'open': 'Open',
    'under_review': 'Reviewing',
    'resolved': 'Resolved',
    'dismissed': 'Dismissed',
  };
  static const _categories = {
    'service_problem': 'Service problem',
    'payment_issue': 'Payment issue',
    'no_show': 'No-show',
    'misconduct': 'Misconduct',
    'sexual_conduct': 'Inappropriate or sexual conduct',
    'other': 'Other',
  };

  String _filter = 'open';
  bool _loading = true;
  List<Map<String, dynamic>> _all = [];
  List<Map<String, dynamic>> get _disputes => _all.where((d) => d['status'] == _filter).toList();
  int _count(String status) => _all.where((d) => d['status'] == status).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('disputes')
          .select('*, bookings(booking_time, total_price, services(service_name)), '
              'reporter:profiles!disputes_reporter_id_fkey(full_name), '
              'reported:profiles!disputes_reported_user_id_fkey(full_name, is_banned)')
          .order('created_at', ascending: false)
          .limit(300);
      if (mounted) {
        setState(() {
          // Sexual-conduct reports first, then newest.
          _all = List<Map<String, dynamic>>.from(data)
            ..sort((a, b) {
              final sa = a['category'] == 'sexual_conduct' ? 0 : 1, sb = b['category'] == 'sexual_conduct' ? 0 : 1;
              return sa != sb ? sa - sb : (b['created_at'] ?? '').compareTo(a['created_at'] ?? '');
            });
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not load disputes: $e')));
      }
    }
  }

  Future<void> _update(Map<String, dynamic> d, String status, String resolution) async {
    final final_ = status == 'resolved' || status == 'dismissed';
    await supabase.from('disputes').update({
      'status': status,
      'resolution': resolution.isEmpty ? null : resolution,
      if (final_) 'resolved_by': supabase.auth.currentUser!.id,
      if (final_) 'resolved_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', d['id']);

    if (final_) {
      await supabase.from('notifications').insert({
        'user_id': d['reporter_id'],
        'type': 'dispute',
        'title': status == 'resolved' ? 'Your report was resolved' : 'Your report was closed',
        'body': resolution.isEmpty ? 'Thank you for letting us know.' : resolution,
        'reference_id': d['booking_id'],
      });
    }
    _load();
  }

  /// Suspends the reported account, cancels their upcoming bookings and
  /// closes this report. Asks first because it's serious.
  Future<void> _ban(Map<String, dynamic> d) async {
    final name = d['reported']?['full_name'] ?? 'this account';
    final reasonCtrl = TextEditingController(
        text: d['category'] == 'sexual_conduct' ? 'Inappropriate or sexual conduct' : (_categories[d['category']] ?? ''));
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ban $name?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('They\'ll be signed out and can\'t sign in again. Their upcoming bookings are cancelled '
              'and those clients or pros are told why. A pro also disappears from Browse.'),
          const SizedBox(height: 12),
          TextField(
            controller: reasonCtrl,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Reason (only admins see this)'),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ban account'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final r = await supabase.rpc('admin_set_ban', params: {
        'p_user': d['reported_user_id'],
        'p_ban': true,
        'p_reason': reasonCtrl.text.trim(),
        'p_dispute': d['id'],
      });
      final n = (r is Map ? r['cancelled'] : 0) ?? 0;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('$name is banned.${n > 0 ? ' $n upcoming booking${n == 1 ? '' : 's'} cancelled.' : ''}')));
      }
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  void _open(Map<String, dynamic> d) {
    final resolutionCtrl = TextEditingController(text: d['resolution'] ?? '');
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl))),
      builder: (ctx) => SheetScroll(child: Padding(
        padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl,
            MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_categories[d['category']] ?? 'Report',
                style: Theme.of(ctx).textTheme.titleLarge),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${d['reporter']?['full_name'] ?? 'User'} reported ${d['reported']?['full_name'] ?? 'the other party'}',
              style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(d['description'] ?? '', style: Theme.of(ctx).textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.lg),
            TextField(
              controller: resolutionCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Resolution / note to the reporter',
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.sm, children: [
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/booking/${d['booking_id']}');
                },
                child: const Text('View booking'),
              ),
              if (d['status'] == 'open')
                OutlinedButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _update(d, 'under_review', resolutionCtrl.text.trim());
                  },
                  child: const Text('Mark reviewing'),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _update(d, 'dismissed', resolutionCtrl.text.trim());
                },
                child: const Text('Dismiss'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _update(d, 'resolved', resolutionCtrl.text.trim());
                },
                child: const Text('Resolve'),
              ),
            ]),
            if (d['reported_user_id'] != null) ...[
              const SizedBox(height: AppSpacing.lg),
              if (d['reported']?['is_banned'] == true)
                Row(children: [
                  Icon(TablerIcons.ban, color: AppColors.error, size: 18),
                  const SizedBox(width: 8),
                  Text('${d['reported']?['full_name'] ?? 'This account'} is banned',
                      style: TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)),
                ])
              else
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                    side: BorderSide(color: AppColors.error),
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _ban(d);
                  },
                  icon: const Icon(TablerIcons.ban, size: 18),
                  label: Text('Ban ${d['reported']?['full_name'] ?? 'reported account'}'),
                ),
            ],
          ],
        ),
      )),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Disputes')),
      body: Column(children: [
        SizedBox(
          height: 56,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            children: _filters.entries
                .map((e) => Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(
                            (e.key == 'open' || e.key == 'under_review') && _count(e.key) > 0
                                ? '${e.value} (${_count(e.key)})'
                                : e.value),
                        selected: _filter == e.key,
                        onSelected: (_) => setState(() => _filter = e.key),
                      ),
                    ))
                .toList(),
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingPlaceholder()
              : _disputes.isEmpty
                  ? Center(
                      child: Text('No ${_filters[_filter]!.toLowerCase()} disputes',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)))
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: AppSpacing.screenPadding,
                        itemCount: _disputes.length,
                        separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                        itemBuilder: (_, i) {
                          final d = _disputes[i];
                          final created = DateTime.tryParse(d['created_at'] ?? '')?.toLocal();
                          return Card(
                            child: ListTile(
                              onTap: () => _open(d),
                              leading: CircleAvatar(
                                backgroundColor: AppColors.errorSoft,
                                child: Icon(TablerIcons.flag, color: AppColors.error),
                              ),
                              title: Text(_categories[d['category']] ?? 'Report',
                                  style: d['category'] == 'sexual_conduct'
                                      ? TextStyle(color: AppColors.error, fontWeight: FontWeight.w700)
                                      : null),
                              subtitle: Text(
                                '${d['bookings']?['services']?['service_name'] ?? 'Booking'} · '
                                '${d['reporter']?['full_name'] ?? 'User'}'
                                '${created != null ? ' · ${created.day}/${created.month}' : ''}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: const Icon(TablerIcons.chevron_right),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ]),
    );
  }
}
