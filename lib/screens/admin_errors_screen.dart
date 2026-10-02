import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';

import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

/// Crashes and errors people hit in the app, grouped so the same problem is
/// one row with a count. Mark one fixed after shipping the fix; if it happens
/// again it reopens and admins get a notification.
class AdminErrorsScreen extends StatefulWidget {
  const AdminErrorsScreen({super.key});

  @override
  State<AdminErrorsScreen> createState() => _AdminErrorsScreenState();
}

class _AdminErrorsScreenState extends State<AdminErrorsScreen> {
  bool _showFixed = false;
  bool _loading = true;
  List<Map<String, dynamic>> _errors = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      var q = supabase.from('app_errors').select();
      q = _showFixed ? q.not('resolved_at', 'is', null) : q.isFilter('resolved_at', null);
      final data = await q.order('last_seen', ascending: false).limit(200);
      if (mounted) {
        setState(() {
          _errors = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not load errors: $e')));
      }
    }
  }

  Future<void> _setFixed(Map<String, dynamic> e, bool fixed) async {
    await supabase
        .from('app_errors')
        .update({'resolved_at': fixed ? DateTime.now().toUtc().toIso8601String() : null}).eq('id', e['id']);
    _load();
  }

  static String _ago(String? iso) {
    final t = DateTime.tryParse(iso ?? '')?.toLocal();
    if (t == null) return '';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes} min ago';
    if (d.inDays < 1) return '${d.inHours} h ago';
    if (d.inDays < 30) return '${d.inDays} d ago';
    return '${t.day}/${t.month}/${t.year}';
  }

  void _open(Map<String, dynamic> e) {
    final details = [
      e['message'],
      'Page: ${e['route'] ?? '-'} · ${e['platform'] ?? '-'} · version ${e['app_version'] ?? '-'}',
      'Seen ${e['count']} times by ${e['users_affected']} people. First ${_ago(e['first_seen'])}, last ${_ago(e['last_seen'])}.',
      '',
      e['stack'] ?? '(no stack trace)',
    ].join('\n');
    showModalBottomSheet(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => SheetScroll(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(e['message'] ?? '', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              const SizedBox(height: 8),
              Text(
                'Page ${e['route'] ?? '-'} · ${e['platform'] ?? '-'} · v${e['app_version'] ?? '-'}\n'
                '${e['count']} times · ${e['users_affected']} ${e['users_affected'] == 1 ? 'person' : 'people'} · '
                'first ${_ago(e['first_seen'])} · last ${_ago(e['last_seen'])}',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
                child: SelectableText(
                  e['stack'] ?? '(no stack trace)',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5, height: 1.35),
                ),
              ),
              const SizedBox(height: 14),
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: details));
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Copied')));
                    },
                    icon: const Icon(TablerIcons.copy, size: 18),
                    label: const Text('Copy details'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _setFixed(e, e['resolved_at'] == null);
                    },
                    child: Text(e['resolved_at'] == null ? 'Mark fixed' : 'Reopen'),
                  ),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('App errors')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(children: [
            ChoiceChip(
              label: const Text('Happening'),
              selected: !_showFixed,
              onSelected: (_) {
                setState(() => _showFixed = false);
                _load();
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Fixed'),
              selected: _showFixed,
              onSelected: (_) {
                setState(() => _showFixed = true);
                _load();
              },
            ),
          ]),
        ),
        Expanded(
          child: _loading
              ? const LoadingPlaceholder()
              : _errors.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Icon(TablerIcons.mood_happy, size: 40, color: AppColors.success),
                          const SizedBox(height: 10),
                          Text(_showFixed ? 'Nothing marked fixed yet' : 'No errors right now',
                              style: TextStyle(color: AppColors.textSecondary)),
                        ]),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                        itemCount: _errors.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          final e = _errors[i];
                          final people = (e['users_affected'] as num?)?.toInt() ?? 1;
                          return Card(
                            child: ListTile(
                              onTap: () => _open(e),
                              leading: CircleAvatar(
                                backgroundColor: people >= 5 ? AppColors.errorSoft : AppColors.surfaceMuted,
                                child: Icon(TablerIcons.bug,
                                    color: people >= 5 ? AppColors.error : AppColors.textSecondary),
                              ),
                              title: Text(e['message'] ?? '', maxLines: 2, overflow: TextOverflow.ellipsis),
                              subtitle: Text(
                                '${e['count']}× · $people ${people == 1 ? 'person' : 'people'} · '
                                '${e['platform'] ?? ''} · ${_ago(e['last_seen'])}',
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
