import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../widgets/ui.dart';

/// Stylist's client list: everyone who has booked, in the app or added by hand.
class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key});
  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _clients = [];
  String _q = '';
  String? _tag;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await supabase.rpc('my_clients') as List;
      if (mounted) {
        setState(() {
          _clients = List<Map<String, dynamic>>.from(rows);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<String> get _allTags {
    final t = <String>{};
    for (final c in _clients) {
      t.addAll(((c['tags'] as List?) ?? []).cast<String>());
    }
    return t.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final list = _clients.where((c) {
      final tags = ((c['tags'] as List?) ?? []).cast<String>();
      if (_tag != null && !tags.contains(_tag)) return false;
      if (_q.isEmpty) return true;
      return (c['name'] ?? '').toString().toLowerCase().contains(_q) ||
          (c['phone'] ?? '').toString().contains(_q);
    }).toList();
    final totalSpend = _clients.fold<num>(0, (s, c) => s + ((c['total_spent'] as num?) ?? 0));

    return Scaffold(
      appBar: AppBar(title: const Text('Clients')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          await context.push('/provider/add-booking');
          _load();
        },
        icon: const Icon(Icons.add),
        label: const Text('Add booking'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _clients.isEmpty
                  ? ListView(children: const [
                      SizedBox(height: 80),
                      EmptyState(
                        icon: Icons.people_outline_rounded,
                        title: 'No clients yet',
                        message: 'Everyone who books you, in the app or added by you, shows up here with their visits and spend.',
                      ),
                    ])
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 100), children: [
                      Row(children: [
                        Expanded(child: _Stat(value: '${_clients.length}', label: 'Clients')),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _Stat(
                              value: '${_clients.where((c) => ((c['visits'] as num?) ?? 0) >= 2).length}',
                              label: 'Regulars'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: _Stat(value: money(totalSpend), label: 'Lifetime spend')),
                      ]),
                      const SizedBox(height: 12),
                      TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          hintText: 'Search name or phone',
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                      ),
                      if (_allTags.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        SizedBox(
                          height: 36,
                          child: ListView(scrollDirection: Axis.horizontal, children: [
                            for (final t in _allTags)
                              Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: FilterChip(
                                  label: Text(t),
                                  selected: _tag == t,
                                  onSelected: (on) => setState(() => _tag = on ? t : null),
                                ),
                              ),
                          ]),
                        ),
                      ],
                      const SizedBox(height: 8),
                      for (final c in list) _ClientRow(client: c, onChanged: _load),
                      if (list.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(child: Text('No clients match.')),
                        ),
                    ]),
            ),
    );
  }
}

class _Stat extends StatelessWidget {
  final String value;
  final String label;
  const _Stat({required this.value, required this.label});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(children: [
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 2),
        Text(label,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11.5, color: AppColors.textTertiary)),
      ]),
    );
  }
}

String _shortDate(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}${d.year != DateTime.now().year ? ' ${d.year}' : ''}';
}

class _ClientRow extends StatelessWidget {
  final Map<String, dynamic> client;
  final VoidCallback onChanged;
  const _ClientRow({required this.client, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final c = client;
    final visits = (c['visits'] as num?)?.toInt() ?? 0;
    final tags = ((c['tags'] as List?) ?? []).cast<String>();
    final next = c['next_booking'] as String?;
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: () async {
        await context.push('/provider/clients/${Uri.encodeComponent(c['client_key'])}');
        onChanged();
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.border),
        ),
        child: Row(children: [
          PersonAvatar(name: c['name'] ?? 'C', size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(c['name'] ?? 'Client',
                      overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                ),
                if (c['client_id'] == null) ...[
                  const SizedBox(width: 6),
                  const Pill(label: 'Walk-in', color: AppColors.textTertiary),
                ],
              ]),
              const SizedBox(height: 2),
              Text(
                [
                  '$visits ${visits == 1 ? 'visit' : 'visits'}',
                  if (visits > 0) money((c['total_spent'] as num?) ?? 0),
                  if (next != null) 'next ${_shortDate(next)}' else if (c['last_visit'] != null) 'last ${_shortDate(c['last_visit'])}',
                ].join(' · '),
                style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
              ),
              if (tags.isNotEmpty) ...[
                const SizedBox(height: 6),
                Wrap(spacing: 4, runSpacing: 4, children: [
                  for (final t in tags.take(3)) Pill(label: t, color: AppColors.primary),
                ]),
              ],
            ]),
          ),
          const Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
        ]),
      ),
    );
  }
}

/// One client's record: history, spend, notes and tags.
class ClientDetailScreen extends StatefulWidget {
  final String clientKey;
  const ClientDetailScreen({super.key, required this.clientKey});
  @override
  State<ClientDetailScreen> createState() => _ClientDetailScreenState();
}

class _ClientDetailScreenState extends State<ClientDetailScreen> {
  static const _suggested = ['VIP', 'Regular', 'Sensitive scalp', 'Prefers mornings', 'Late payer', 'Allergies'];

  bool _loading = true;
  Map<String, dynamic>? _client;
  List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _oldNotes = [];
  final _notesCtrl = TextEditingController();
  List<String> _tags = [];
  bool _dirty = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      final results = await Future.wait<dynamic>([
        supabase.rpc('my_clients'),
        supabase.rpc('client_history', params: {'p_key': widget.clientKey}),
        supabase.from('client_records').select().eq('provider_id', uid).eq('client_key', widget.clientKey).maybeSingle(),
      ]);
      _client = List<Map<String, dynamic>>.from(results[0] as List)
          .where((c) => c['client_key'] == widget.clientKey)
          .firstOrNull;
      _history = List<Map<String, dynamic>>.from(results[1] as List);
      final rec = results[2] as Map<String, dynamic>?;
      _notesCtrl.text = rec?['notes'] ?? '';
      _tags = ((rec?['tags'] as List?) ?? []).cast<String>();
      final cid = _client?['client_id'];
      if (cid != null) {
        _oldNotes = List<Map<String, dynamic>>.from(await supabase
            .from('client_notes')
            .select('note, created_at')
            .eq('provider_id', uid)
            .eq('client_id', cid)
            .order('created_at', ascending: false));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await supabase.from('client_records').upsert({
        'provider_id': supabase.auth.currentUser!.id,
        'client_key': widget.clientKey,
        'tags': _tags,
        'notes': _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      if (mounted) {
        setState(() => _dirty = false);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addTag() async {
    final ctrl = TextEditingController();
    final t = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a tag'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 24,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'e.g. Knotless only'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Add')),
        ],
      ),
    );
    ctrl.dispose();
    if (t != null && t.isNotEmpty && !_tags.contains(t) && _tags.length < 12) {
      setState(() {
        _tags = [..._tags, t];
        _dirty = true;
      });
    }
  }

  @override
  void dispose() {
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final c = _client;
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.person_off_outlined, title: 'Client not found', message: 'They have no bookings with you.'),
      );
    }
    final phone = c['phone'] as String?;
    final visits = (c['visits'] as num?)?.toInt() ?? 0;
    final spent = (c['total_spent'] as num?) ?? 0;
    final noShows = (c['no_shows'] as num?)?.toInt() ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Client'),
        actions: [
          if (_dirty)
            TextButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(20, 4, 20, 40), children: [
        Row(children: [
          PersonAvatar(name: c['name'] ?? 'C', size: 60),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(c['name'] ?? 'Client', style: Theme.of(context).textTheme.headlineSmall),
              Text(
                [if (phone != null) phone, c['client_id'] == null ? 'Added by you' : 'BeauTap client'].join(' · '),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ]),
          ),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _Stat(value: '$visits', label: visits == 1 ? 'Visit' : 'Visits')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(value: money(spent), label: 'Spent')),
          const SizedBox(width: 10),
          Expanded(child: _Stat(value: visits == 0 ? '—' : money(spent / visits), label: 'Per visit')),
        ]),
        if (noShows > 0) ...[
          const SizedBox(height: 10),
          Text('$noShows no-show${noShows == 1 ? '' : 's'}',
              style: const TextStyle(color: AppColors.error, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: () async {
                await context.push('/provider/add-booking?client=${Uri.encodeComponent(widget.clientKey)}');
                _load();
              },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Book again'),
            ),
          ),
          if (phone != null) ...[
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => shareOnWhatsApp('Hi ${(c['name'] ?? '').toString().split(' ').first}, ', phone: phone),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('WhatsApp'),
              ),
            ),
          ],
        ]),
        const SizedBox(height: 24),
        Text('Tags', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final t in _tags)
            InputChip(
              label: Text(t),
              onDeleted: () => setState(() {
                _tags = _tags.where((x) => x != t).toList();
                _dirty = true;
              }),
            ),
          for (final t in _suggested.where((s) => !_tags.contains(s)).take(4))
            ActionChip(
              avatar: const Icon(Icons.add, size: 16),
              label: Text(t),
              onPressed: () => setState(() {
                _tags = [..._tags, t];
                _dirty = true;
              }),
            ),
          ActionChip(avatar: const Icon(Icons.edit_outlined, size: 16), label: const Text('Other'), onPressed: _addTag),
        ]),
        const SizedBox(height: 20),
        Text('Private notes', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        TextField(
          controller: _notesCtrl,
          minLines: 3,
          maxLines: 8,
          maxLength: 4000,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: const InputDecoration(
            hintText: 'Hair type, products used, colour formula, preferences… Only you can see this.',
          ),
        ),
        if (_dirty)
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save notes and tags')),
        if (_oldNotes.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('Earlier notes', style: Theme.of(context).textTheme.titleSmall),
          for (final n in _oldNotes)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${_shortDate(n['created_at'])} — ${n['note']}',
                  style: const TextStyle(fontSize: 13.5, color: AppColors.textSecondary)),
            ),
        ],
        const SizedBox(height: 24),
        Text('History', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        for (final h in _history)
          InkWell(
            onTap: () => context.push('/booking/${h['id']}'),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(children: [
                SizedBox(
                  width: 64,
                  child: Text(_shortDate(h['booking_time']),
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                ),
                Expanded(child: Text(h['service_name'] ?? 'Service', overflow: TextOverflow.ellipsis)),
                const SizedBox(width: 8),
                Pill(
                  label: h['no_show'] == true ? 'No-show' : (h['status'] as String).replaceFirst(h['status'][0], h['status'][0].toUpperCase()),
                  color: StatusColors.foreground(h['no_show'] == true ? 'cancelled' : h['status']),
                ),
                const SizedBox(width: 8),
                Text(money((h['total_price'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
      ]),
    );
  }
}
