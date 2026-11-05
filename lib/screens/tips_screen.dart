import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../widgets/ui.dart';

const tipCategories = ['Aftercare', 'Trending', 'How-to', 'Hair care', 'Skin', 'Nails', 'Barbering'];
const _tipSelect = 'id, title, body, category, cover_url, service_id, by_beautap, is_hidden, hidden_reason, created_at, author_id, '
    'author:profiles!tips_author_id_fkey(full_name, avatar_url, is_verified), services(service_name, price)';

Future<List<Map<String, dynamic>>> loadTips({int limit = 30, String? category}) async {
  try {
    var q = supabase.from('tips').select(_tipSelect).eq('is_hidden', false);
    if (category != null) q = q.eq('category', category);
    return List<Map<String, dynamic>>.from(await q.order('created_at', ascending: false).limit(limit));
  } catch (_) {
    return const [];
  }
}

Future<bool> _canWrite() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null || supabase.auth.currentUser!.isAnonymous) return false;
  try {
    final r = await Future.wait<dynamic>([
      supabase.from('profiles').select('is_verified').eq('id', uid).maybeSingle(),
      supabase.from('admins').select('user_id').eq('user_id', uid),
    ]);
    return (r[0] as Map?)?['is_verified'] == true || (r[1] as List).isNotEmpty;
  } catch (_) {
    return false;
  }
}

Future<bool> _isAdmin() async {
  final uid = supabase.auth.currentUser?.id;
  if (uid == null) return false;
  try {
    return (await supabase.from('admins').select('user_id').eq('user_id', uid) as List).isNotEmpty;
  } catch (_) {
    return false;
  }
}

String _ago(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${d.day} ${m[d.month - 1]}';
}

int _minutes(String body) => (body.split(RegExp(r'\s+')).length / 200).ceil().clamp(1, 30);

/// The small "B" square used when a tip is from BeauTap.
class _BeauTapMark extends StatelessWidget {
  final double size;
  const _BeauTapMark({this.size = 20});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(color: const Color(0xFF141210), borderRadius: BorderRadius.circular(size * 0.3)),
        child: Text('B', style: TextStyle(fontFamily: 'InterDisplay', fontWeight: FontWeight.w700, fontSize: size * 0.55, color: AppColors.gold)),
      );
}

Widget _byline(Map<String, dynamic> t, {double size = 20}) {
  final a = t['author'] as Map? ?? {};
  final name = t['by_beautap'] == true ? 'BeauTap' : (a['full_name'] ?? 'BeauTap pro').toString();
  return Row(children: [
    if (t['by_beautap'] == true)
      _BeauTapMark(size: size)
    else
      PersonAvatar(name: name, url: a['avatar_url'] as String?, size: size),
    const SizedBox(width: 6),
    Flexible(
      child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
    ),
  ]);
}

Widget _cover(Map<String, dynamic> t, {double? height}) {
  final url = (t['cover_url'] ?? '').toString();
  if (url.isEmpty) {
    return Container(
      height: height,
      decoration: const BoxDecoration(gradient: LinearGradient(colors: [Color(0xFF2A2116), Color(0xFF141210)])),
      alignment: Alignment.center,
      child: const Icon(TablerIcons.sparkles, color: AppColors.gold, size: 32),
    );
  }
  return Image.network(url, height: height, width: double.infinity, fit: BoxFit.cover, cacheWidth: 900,
      errorBuilder: (_, _, _) => Container(height: height, color: AppColors.surfaceMuted));
}

/// A tip card for the Home row and the feed.
class TipCard extends StatelessWidget {
  final Map<String, dynamic> tip;
  final double width;
  const TipCard({super.key, required this.tip, this.width = 230});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Material(
        color: AppColors.card,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/tips/${tip['id']}'),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(height: 130, width: double.infinity, child: _cover(tip, height: 130)),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((tip['category'] ?? '').toString().toUpperCase(),
                    style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.goldText)),
                const SizedBox(height: 3),
                Text(tip['title'] ?? '',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 14.5, height: 1.3, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                _byline(tip),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

/// "Tips & trends" on Home: a horizontal row of the newest tips.
class TipsRow extends StatefulWidget {
  const TipsRow({super.key});
  @override
  State<TipsRow> createState() => _TipsRowState();
}

class _TipsRowState extends State<TipsRow> {
  List<Map<String, dynamic>> _tips = [];

  @override
  void initState() {
    super.initState();
    loadTips(limit: 8).then((t) {
      if (mounted) setState(() => _tips = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_tips.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(0, 22, 0, 12),
        child: Row(children: [
          Expanded(
            child: Text('Tips & trends',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -0.2, color: AppColors.textPrimary)),
          ),
          GestureDetector(
            onTap: () => context.push('/tips'),
            child: Text('See all', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: AppColors.goldText)),
          ),
        ]),
      ),
      SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          itemCount: _tips.length,
          separatorBuilder: (_, _) => const SizedBox(width: 12),
          itemBuilder: (_, i) => TipCard(tip: _tips[i]),
        ),
      ),
    ]);
  }
}

// =====================================================================
// Feed
// =====================================================================

class TipsFeedScreen extends StatefulWidget {
  const TipsFeedScreen({super.key});
  @override
  State<TipsFeedScreen> createState() => _TipsFeedScreenState();
}

class _TipsFeedScreenState extends State<TipsFeedScreen> {
  bool _loading = true;
  bool _canPost = false;
  String? _cat;
  List<Map<String, dynamic>> _tips = [];

  @override
  void initState() {
    super.initState();
    _load();
    _canWrite().then((v) {
      if (mounted) setState(() => _canPost = v);
    });
  }

  Future<void> _load() async {
    final t = await loadTips(limit: 60, category: _cat);
    if (mounted) {
      setState(() {
        _tips = t;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Tips & trends')),
      floatingActionButton: _canPost
          ? FloatingActionButton.extended(
              onPressed: () => context.push('/tips/new').then((_) => _load()),
              icon: const Icon(TablerIcons.pencil),
              label: const Text('Write a tip'),
            )
          : null,
      body: Column(children: [
        SizedBox(
          height: 52,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            children: [
              for (final c in [null, ...tipCategories])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c ?? 'All'),
                    selected: _cat == c,
                    showCheckmark: false,
                    onSelected: (_) {
                      Haptics.light();
                      setState(() {
                        _cat = c;
                        _loading = true;
                      });
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const LoadingPlaceholder()
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: _tips.isEmpty
                      ? ListView(children: const [
                          SizedBox(height: 60),
                          EmptyState(
                            icon: TablerIcons.sparkles,
                            title: 'No tips here yet',
                            message: 'Beauty pros and BeauTap share aftercare, trends and how-tos here.',
                          ),
                        ])
                      : LayoutBuilder(builder: (context, box) {
                          final cols = (box.maxWidth / 300).floor().clamp(1, 4);
                          final w = (box.maxWidth - 32 - 12 * (cols - 1)) / cols;
                          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 100), children: [
                            Wrap(spacing: 12, runSpacing: 12, children: [
                              for (final t in _tips) TipCard(tip: t, width: w),
                            ]),
                          ]);
                        }),
                ),
        ),
      ]),
    );
  }
}

// =====================================================================
// One tip
// =====================================================================

class TipScreen extends StatefulWidget {
  final String tipId;
  const TipScreen({super.key, required this.tipId});
  @override
  State<TipScreen> createState() => _TipScreenState();
}

class _TipScreenState extends State<TipScreen> {
  Map<String, dynamic>? _tip;
  bool _loading = true;
  bool _admin = false;

  @override
  void initState() {
    super.initState();
    _load();
    _isAdmin().then((v) {
      if (mounted) setState(() => _admin = v);
    });
  }

  Future<void> _load() async {
    try {
      _tip = await supabase.from('tips').select(_tipSelect).eq('id', widget.tipId).maybeSingle();
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _hide() async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hide this tip?'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 120,
          decoration: const InputDecoration(labelText: 'Reason (the author sees this)', hintText: 'e.g. Medical claims'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Hide')),
        ],
      ),
    );
    if (reason == null) return;
    try {
      await supabase.from('tips').update({'is_hidden': true, 'hidden_reason': reason.isEmpty ? null : reason}).eq('id', widget.tipId);
      Haptics.warn();
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  Future<void> _unhide() async {
    await supabase.from('tips').update({'is_hidden': false, 'hidden_reason': null}).eq('id', widget.tipId);
    _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this tip?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await supabase.from('tips').delete().eq('id', widget.tipId);
    if (mounted) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingPlaceholder(kind: PlaceholderKind.detail));
    final t = _tip;
    if (t == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: TablerIcons.sparkles, title: 'Tip not found', message: 'It may have been removed.'),
      );
    }
    final a = t['author'] as Map? ?? {};
    final mine = t['author_id'] == supabase.auth.currentUser?.id;
    final service = t['services'] as Map?;
    final authorName = t['by_beautap'] == true ? 'BeauTap' : (a['full_name'] ?? '').toString();
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          stretch: true,
          actions: [
            if (mine || _admin)
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') context.push('/tips/${t['id']}/edit').then((_) => _load());
                  if (v == 'hide') _hide();
                  if (v == 'unhide') _unhide();
                  if (v == 'delete') _delete();
                },
                itemBuilder: (_) => [
                  if (mine) const PopupMenuItem(value: 'edit', child: Text('Edit')),
                  if (_admin && t['is_hidden'] != true) const PopupMenuItem(value: 'hide', child: Text('Hide (admin)')),
                  if (_admin && t['is_hidden'] == true) const PopupMenuItem(value: 'unhide', child: Text('Show again (admin)')),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
          ],
          flexibleSpace: FlexibleSpaceBar(background: _cover(t, height: 340)),
        ),
        SliverToBoxAdapter(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (t['is_hidden'] == true)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: SoftBanner(
                        icon: TablerIcons.eye_off,
                        color: AppColors.errorText,
                        title: 'Hidden',
                        message: t['hidden_reason'] ?? 'Only you and admins can see this tip.',
                      ),
                    ),
                  Text('${(t['category'] ?? '').toString().toUpperCase()} · ${_minutes(t['body'] ?? '')} MIN READ',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: AppColors.goldText)),
                  const SizedBox(height: 8),
                  Text(t['title'] ?? '',
                      style: TextStyle(
                          fontFamily: AppTheme.displayFamily,
                          fontSize: 27,
                          height: 1.15,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.5,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  InkWell(
                    onTap: t['by_beautap'] == true ? null : () => context.push('/provider/${t['author_id']}'),
                    child: Row(children: [
                      if (t['by_beautap'] == true)
                        const _BeauTapMark(size: 34)
                      else
                        PersonAvatar(name: authorName, url: a['avatar_url'] as String?, size: 34),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('$authorName${a['is_verified'] == true && t['by_beautap'] != true ? ' ✔' : ''}',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                          Text(_ago(t['created_at']), style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                        ]),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 14),
                  SelectableText(t['body'] ?? '', style: TextStyle(fontSize: 15.5, height: 1.6, color: AppColors.textPrimary)),
                  if (service != null && t['by_beautap'] != true) ...[
                    const SizedBox(height: 18),
                    Material(
                      color: AppColors.card,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: () => context.push('/provider/${t['author_id']}'),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(children: [
                            PersonAvatar(name: authorName, url: a['avatar_url'] as String?, size: 46),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${service['service_name']} with ${authorName.split(' ').first}',
                                    style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                if (service['price'] != null)
                                  Text('from \$${(service['price'] as num).toStringAsFixed(0)}',
                                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                              ]),
                            ),
                            FilledButton(
                              onPressed: () => context.push('/book/${t['author_id']}/${t['service_id']}'),
                              style: FilledButton.styleFrom(minimumSize: const Size(0, 38), shape: const StadiumBorder()),
                              child: const Text('Book'),
                            ),
                          ]),
                        ),
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

// =====================================================================
// Write / edit
// =====================================================================

class TipEditorScreen extends StatefulWidget {
  final String? tipId;
  const TipEditorScreen({super.key, this.tipId});
  @override
  State<TipEditorScreen> createState() => _TipEditorScreenState();
}

class _TipEditorScreenState extends State<TipEditorScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  String _cat = 'Aftercare';
  String? _cover;
  String? _serviceId;
  bool _asBeauTap = false;
  bool _admin = false;
  bool _allowed = true;
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;
  List<Map<String, dynamic>> _services = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser!.id;
    _allowed = await _canWrite();
    _admin = await _isAdmin();
    try {
      _services = List<Map<String, dynamic>>.from(
          await supabase.from('services').select('id, service_name').eq('provider_id', uid).eq('is_active', true));
      if (widget.tipId != null) {
        final t = await supabase.from('tips').select().eq('id', widget.tipId!).single();
        _title.text = t['title'] ?? '';
        _body.text = t['body'] ?? '';
        _cat = t['category'] ?? _cat;
        _cover = t['cover_url'];
        _serviceId = t['service_id'];
        _asBeauTap = t['by_beautap'] == true;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickCover() async {
    final img = await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1600, maxHeight: 1600, imageQuality: 82);
    if (img == null) return;
    setState(() => _uploading = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final path = '$uid/tip_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await supabase.storage.from('hairstyle-gallery').uploadBinary(path, await img.readAsBytes());
      setState(() => _cover = supabase.storage.from('hairstyle-gallery').getPublicUrl(path));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not upload the photo: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    final body = _body.text.trim();
    String? problem;
    if (title.length < 5) problem = 'Give your tip a title (at least 5 characters)';
    if (body.length < 40) problem ??= 'Write a little more: at least a few sentences';
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem), backgroundColor: AppColors.error));
      return;
    }
    setState(() => _saving = true);
    try {
      final row = {
        'author_id': supabase.auth.currentUser!.id,
        'title': title,
        'body': body,
        'category': _cat,
        'cover_url': _cover,
        'service_id': _asBeauTap ? null : _serviceId,
        if (_admin) 'by_beautap': _asBeauTap,
      };
      String id;
      if (widget.tipId == null) {
        id = (await supabase.from('tips').insert(row).select('id').single())['id'];
      } else {
        id = widget.tipId!;
        await supabase.from('tips').update(row).eq('id', id);
      }
      Haptics.firm();
      if (mounted) context.pushReplacement('/tips/$id');
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingPlaceholder());
    if (!_allowed) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: TablerIcons.rosette_discount_check,
          title: 'For verified pros',
          message: 'Get your ID verified to share tips with clients. It also adds the verified badge to your profile.',
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.tipId == null ? 'Write a tip' : 'Edit tip')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
            InkWell(
              onTap: _uploading ? null : _pickCover,
              borderRadius: BorderRadius.circular(18),
              child: Container(
                height: 170,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: _cover == null ? Border.all(color: AppColors.borderStrong, width: 1.5) : null,
                ),
                child: _cover != null
                    ? Image.network(_cover!, fit: BoxFit.cover, width: double.infinity)
                    : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(_uploading ? TablerIcons.loader : TablerIcons.photo_plus, color: AppColors.textSecondary),
                        const SizedBox(height: 6),
                        Text(_uploading ? 'Uploading…' : 'Add a cover photo of your work',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ]),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in tipCategories)
                ChoiceChip(
                  label: Text(c),
                  selected: _cat == c,
                  showCheckmark: false,
                  onSelected: (_) => setState(() => _cat = c),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              maxLength: 90,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Title', hintText: 'e.g. Make knotless braids last 8 weeks'),
            ),
            TextField(
              controller: _body,
              maxLength: 6000,
              minLines: 8,
              maxLines: 20,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(labelText: 'Your tip', alignLabelWithHint: true),
            ),
            if (_admin)
              SwitchListTile.adaptive(
                value: _asBeauTap,
                onChanged: (v) => setState(() => _asBeauTap = v),
                contentPadding: EdgeInsets.zero,
                activeTrackColor: AppColors.gold,
                title: const Text('Post as BeauTap'),
                subtitle: const Text('Shows the BeauTap name instead of yours'),
              ),
            if (!_asBeauTap && _services.isNotEmpty)
              DropdownButtonFormField<String?>(
                initialValue: _services.any((s) => s['id'] == _serviceId) ? _serviceId : null,
                decoration: const InputDecoration(labelText: 'Link one of your services (optional)'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  for (final s in _services) DropdownMenuItem(value: s['id'] as String, child: Text(s['service_name'] ?? '')),
                ],
                onChanged: (v) => setState(() => _serviceId = v),
              ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: BorderRadius.circular(16)),
              child: Text(
                'Your tip goes live straight away with your name${_asBeauTap ? '' : ' and a Book button'}. '
                'BeauTap can hide tips that break the rules: no medical claims, no adverts for other apps, only your own photos.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 54,
              child: FilledButton(
                onPressed: _saving || _uploading ? null : _save,
                style: FilledButton.styleFrom(shape: const StadiumBorder()),
                child: Text(_saving ? 'Publishing…' : widget.tipId == null ? 'Publish tip' : 'Save'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
