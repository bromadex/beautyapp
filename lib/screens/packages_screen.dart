import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart' show shareOnWhatsApp;
import '../utils/feel.dart';
import '../utils/pay_methods.dart';
import '../widgets/packages.dart';
import '../widgets/ui.dart';

void _toast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

List<BoxShadow>? get _shadow => AppColors.isDark ? null : AppShadows.lifted;

Widget _label(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(t.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
        ?trailing,
      ]),
    );

Widget _pill(String t, Color fg) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: fg.withValues(alpha: 0.13), borderRadius: AppRadius.pill),
      child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
    );

const _green = Color(0xFF1F8A4C);

// =====================================================================
// Pro: my packages
// =====================================================================

class ProPackagesScreen extends StatefulWidget {
  const ProPackagesScreen({super.key});
  @override
  State<ProPackagesScreen> createState() => _ProPackagesScreenState();
}

class _ProPackagesScreenState extends State<ProPackagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _packages = [];
  Map<String, List<dynamic>> _members = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      final rows = await supabase
          .from('monthly_packages')
          .select('id, name, description, price, is_active, '
              'monthly_package_items(quantity, service_id, tier_id, services(service_name, price), service_tiers(name, price))')
          .eq('provider_id', uid)
          .order('created_at');
      _packages = List<Map<String, dynamic>>.from(rows);
      final m = <String, List<dynamic>>{};
      for (final p in _packages.where((p) => p['is_active'] == true)) {
        try {
          m[p['id']] = await supabase.rpc('package_members_for', params: {'p_package': p['id']}) as List;
        } catch (_) {}
      }
      _members = m;
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly packages')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/provider/packages/new').then((_) => _load()),
        icon: const Icon(TablerIcons.plus),
        label: const Text('New package'),
      ),
      body: _loading
          ? const LoadingPlaceholder()
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 100), children: [
                Text(
                  'Clients pay you directly each month, the same way as deposits. You tap "Received" and their visits unlock. BeauTap takes no fee.',
                  style: TextStyle(fontSize: 13.5, height: 1.45, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 14),
                if (_packages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: TablerIcons.calendar_repeat,
                      title: 'No packages yet',
                      message: 'Bundle regular visits into one monthly price, e.g. a braids install plus two touch-ups.',
                    ),
                  ),
                for (final p in _packages) ...[
                  _ProPackageTile(
                    pkg: p,
                    members: _members[p['id']] ?? const [],
                    onEdit: () => context.push('/provider/packages/${p['id']}/edit').then((_) => _load()),
                    onMembers: () => context.push('/provider/packages/${p['id']}').then((_) => _load()),
                  ),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
    );
  }
}

class _ProPackageTile extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final List<dynamic> members;
  final VoidCallback onEdit;
  final VoidCallback onMembers;
  const _ProPackageTile({required this.pkg, required this.members, required this.onEdit, required this.onMembers});

  @override
  Widget build(BuildContext context) {
    final active = pkg['is_active'] == true;
    final toCheck = members.where((m) => m['pay_status'] == 'claimed').length;
    final paid = members.where((m) => m['pay_status'] == 'paid').length;
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onMembers,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: _shadow),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text(pkg['name'] ?? '',
                    style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              ),
              Text('${pkgMoney((pkg['price'] as num).toDouble())}/mo',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
            const SizedBox(height: 4),
            Text(packageItems(pkg).map((i) => '${i['quantity']}× ${itemName(i)}').join(' · '),
                style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            const SizedBox(height: 10),
            Row(children: [
              if (!active) _pill('Hidden', AppColors.textSecondary) else ...[
                _pill('${members.length} ${members.length == 1 ? 'member' : 'members'}', AppColors.goldText),
                const SizedBox(width: 6),
                if (paid > 0) _pill('$paid paid', _green),
                if (toCheck > 0) ...[const SizedBox(width: 6), _pill('$toCheck to check', AppColors.warningText)],
              ],
              const Spacer(),
              TextButton(onPressed: onEdit, child: const Text('Edit')),
            ]),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
// Pro: create / edit
// =====================================================================

class PackageEditScreen extends StatefulWidget {
  final String? packageId;
  const PackageEditScreen({super.key, this.packageId});
  @override
  State<PackageEditScreen> createState() => _PackageEditScreenState();
}

class _PackageEditScreenState extends State<PackageEditScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  bool _active = true;
  bool _loading = true;
  bool _saving = false;
  List<Map<String, dynamic>> _services = [];
  final Map<String, int> _qty = {}; // service id -> visits a month

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser!.id;
    try {
      _services = List<Map<String, dynamic>>.from(await supabase
          .from('services')
          .select('id, service_name, price')
          .eq('provider_id', uid)
          .eq('is_active', true)
          .order('created_at'));
      if (widget.packageId != null) {
        final p = await supabase
            .from('monthly_packages')
            .select('*, monthly_package_items(service_id, quantity)')
            .eq('id', widget.packageId!)
            .single();
        _name.text = p['name'] ?? '';
        _price.text = (p['price'] as num).toString();
        _desc.text = p['description'] ?? '';
        _active = p['is_active'] == true;
        for (final i in p['monthly_package_items'] as List) {
          _qty[i['service_id']] = (i['quantity'] as num).toInt();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  double get _worth => _services
      .where((s) => _qty.containsKey(s['id']))
      .fold(0.0, (t, s) => t + ((s['price'] as num?)?.toDouble() ?? 0) * _qty[s['id']]!);

  Future<void> _save() async {
    final price = double.tryParse(_price.text.trim());
    if (_name.text.trim().length < 2) return _toast(context, 'Give the package a name', error: true);
    if (price == null || price <= 0) return _toast(context, 'Enter the price per month', error: true);
    if (_qty.isEmpty) return _toast(context, 'Add at least one service', error: true);
    setState(() => _saving = true);
    try {
      final row = {
        'provider_id': supabase.auth.currentUser!.id,
        'name': _name.text.trim(),
        'price': price,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'is_active': _active,
      };
      String id;
      if (widget.packageId == null) {
        id = (await supabase.from('monthly_packages').insert(row).select('id').single())['id'];
      } else {
        id = widget.packageId!;
        await supabase.from('monthly_packages').update(row).eq('id', id);
        await supabase.from('monthly_package_items').delete().eq('package_id', id);
      }
      await supabase.from('monthly_package_items').insert([
        for (final e in _qty.entries) {'package_id': id, 'service_id': e.key, 'quantity': e.value},
      ]);
      Haptics.firm();
      if (mounted) {
        _toast(context, widget.packageId == null ? 'Package published' : 'Package saved');
        context.pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final price = double.tryParse(_price.text.trim()) ?? 0;
    return Scaffold(
      appBar: AppBar(title: Text(widget.packageId == null ? 'New monthly package' : 'Edit package')),
      body: _loading
          ? const LoadingPlaceholder()
          : ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                maxLength: 60,
                decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Braid care'),
              ),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Price per month',
                  prefixText: '\$ ',
                  helperText: _worth > 0
                      ? 'Worth ${pkgMoney(_worth)} if booked one by one${price > 0 && _worth > price ? ' · clients save ${pkgMoney(_worth - price)}' : ''}'
                      : null,
                ),
              ),
              _label('What\'s included each month'),
              Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: _shadow),
                child: Column(children: [
                  if (_services.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text('Add services first, then build a package from them.',
                          style: TextStyle(color: AppColors.textSecondary)),
                    ),
                  for (final s in _services)
                    _ItemRow(
                      name: s['service_name'] ?? '',
                      price: (s['price'] as num?)?.toDouble() ?? 0,
                      qty: _qty[s['id']] ?? 0,
                      onChanged: (q) => setState(() => q == 0 ? _qty.remove(s['id']) : _qty[s['id']] = q),
                    ),
                ]),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _desc,
                maxLines: 3,
                minLines: 1,
                maxLength: 300,
                decoration: const InputDecoration(
                    labelText: 'Notes for clients (optional)', hintText: 'e.g. Hair not included. Book at least 2 days ahead.'),
              ),
              SwitchListTile.adaptive(
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeTrackColor: AppColors.gold,
                contentPadding: EdgeInsets.zero,
                title: const Text('Show on my profile'),
                subtitle: const Text('Off: hidden from new clients. Current members keep their package.'),
              ),
              const SizedBox(height: 8),
              Text(
                'Unused visits don\'t roll over. Clients can cancel any time before the next month. They pay you directly; BeauTap takes no fee.',
                style: TextStyle(fontSize: 12.5, height: 1.4, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 54,
                child: FilledButton(
                  onPressed: _saving ? null : _save,
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: Text(_saving ? 'Saving…' : widget.packageId == null ? 'Publish package' : 'Save'),
                ),
              ),
            ]),
    );
  }
}

class _ItemRow extends StatelessWidget {
  final String name;
  final double price;
  final int qty;
  final ValueChanged<int> onChanged;
  const _ItemRow({required this.name, required this.price, required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final on = qty > 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 14.5, fontWeight: on ? FontWeight.w600 : FontWeight.w400, color: AppColors.textPrimary)),
            Text('${pkgMoney(price)} each', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        IconButton(
          tooltip: 'Fewer',
          onPressed: on ? () {
            Haptics.light();
            onChanged(qty - 1);
          } : null,
          icon: const Icon(TablerIcons.minus, size: 18),
        ),
        SizedBox(
          width: 28,
          child: Text(on ? '$qty×' : '–',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700, color: on ? AppColors.goldText : AppColors.textTertiary)),
        ),
        IconButton(
          tooltip: 'More',
          onPressed: qty < 31
              ? () {
                  Haptics.light();
                  onChanged(qty + 1);
                }
              : null,
          icon: const Icon(TablerIcons.plus, size: 18),
        ),
      ]),
    );
  }
}

// =====================================================================
// Pro: members of one package
// =====================================================================

class PackageMembersScreen extends StatefulWidget {
  final String packageId;
  const PackageMembersScreen({super.key, required this.packageId});
  @override
  State<PackageMembersScreen> createState() => _PackageMembersScreenState();
}

class _PackageMembersScreenState extends State<PackageMembersScreen> {
  bool _loading = true;
  Map<String, dynamic>? _pkg;
  List<Map<String, dynamic>> _members = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _pkg = await supabase.from('monthly_packages').select('id, name, price').eq('id', widget.packageId).single();
      _members = List<Map<String, dynamic>>.from(
          await supabase.rpc('package_members_for', params: {'p_package': widget.packageId}) as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _received(Map<String, dynamic> m) async {
    try {
      await supabase.rpc('confirm_package_payment', params: {'p_member': m['member_id']});
      Haptics.firm();
      if (mounted) _toast(context, 'Received. ${(m['name'] ?? 'Their').toString().split(' ').first}\'s visits are unlocked.');
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    }
  }

  void _remind(Map<String, dynamic> m) {
    final first = (m['name'] ?? '').toString().split(' ').first;
    shareOnWhatsApp(
      'Hi $first! Just a reminder that your ${_pkg?['name'] ?? 'package'} for this month is '
      '${pkgMoney((m['amount'] as num?) ?? 0)}. Send it when you can and your visits unlock. Thank you!',
      phone: m['phone'] as String?,
    );
  }

  @override
  Widget build(BuildContext context) {
    final toCheck = _members.where((m) => m['pay_status'] == 'claimed').toList();
    final paid = _members.where((m) => m['pay_status'] == 'paid').toList();
    final unpaid = _members.where((m) => m['pay_status'] == 'unpaid').toList();
    final month = paid.fold<num>(0, (s, m) => s + ((m['amount'] as num?) ?? 0));
    final left = paid.fold<int>(0, (s, m) => s + (((m['included'] as num?) ?? 0) - ((m['used'] as num?) ?? 0)).toInt());
    Widget stat(String v, String l) => Expanded(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(18), boxShadow: _shadow),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(v, style: TextStyle(fontFamily: AppTheme.displayFamily, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              Text(l, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
            ]),
          ),
        );
    return Scaffold(
      appBar: AppBar(title: Text(_pkg == null ? 'Members' : '${_pkg!['name']} members')),
      body: _loading
          ? const LoadingPlaceholder()
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
                Row(children: [
                  stat('${_members.length}', 'Members'),
                  const SizedBox(width: 8),
                  stat(pkgMoney(month), 'This month'),
                  const SizedBox(width: 8),
                  stat('$left', 'Visits left'),
                ]),
                if (_members.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: EmptyState(
                      icon: TablerIcons.users,
                      title: 'No members yet',
                      message: 'Clients join from your profile. Share your profile link on WhatsApp to get the first ones.',
                    ),
                  ),
                if (toCheck.isNotEmpty) ...[
                  _label('Waiting for you to confirm'),
                  for (final m in toCheck)
                    _MemberRow(
                      m: m,
                      line: 'Says they sent ${pkgMoney((m['amount'] as num?) ?? 0)}'
                          '${m['method'] != null ? ' · ${payMethodLabel(m['method'])}' : ''}',
                      action: 'Received',
                      onAction: () => _received(m),
                    ),
                ],
                if (paid.isNotEmpty) ...[
                  _label('Paid this month'),
                  for (final m in paid)
                    _MemberRow(m: m, line: '${m['used']} of ${m['included']} visits used', badge: 'Paid'),
                ],
                if (unpaid.isNotEmpty) ...[
                  _label('Not paid this month'),
                  for (final m in unpaid)
                    _MemberRow(
                      m: m,
                      line: m['last_paid'] == null ? 'Joined, first payment to come' : 'Last paid ${_monthName(m['last_paid'])}',
                      action: 'Received',
                      onAction: () => _received(m),
                      secondary: (m['phone'] ?? '').toString().isEmpty ? null : 'Remind',
                      onSecondary: () => _remind(m),
                    ),
                ],
              ]),
            ),
    );
  }

  String _monthName(String iso) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final d = DateTime.tryParse(iso);
    return d == null ? '' : months[d.month - 1];
  }
}

class _MemberRow extends StatelessWidget {
  final Map<String, dynamic> m;
  final String line;
  final String? badge;
  final String? action;
  final VoidCallback? onAction;
  final String? secondary;
  final VoidCallback? onSecondary;
  const _MemberRow({required this.m, required this.line, this.badge, this.action, this.onAction, this.secondary, this.onSecondary});

  @override
  Widget build(BuildContext context) {
    final name = (m['name'] ?? 'Client').toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(20), boxShadow: _shadow),
      child: Row(children: [
        PersonAvatar(name: name, url: m['avatar_url'] as String?, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            Text(line, style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        if (badge != null) _pill(badge!, _green),
        if (secondary != null)
          TextButton(onPressed: onSecondary, child: Text(secondary!)),
        if (action != null)
          FilledButton(
            onPressed: onAction,
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 36), padding: const EdgeInsets.symmetric(horizontal: 14), shape: const StadiumBorder()),
            child: Text(action!),
          ),
      ]),
    );
  }
}

// =====================================================================
// Client: my packages
// =====================================================================

class MyPackagesScreen extends StatefulWidget {
  const MyPackagesScreen({super.key});
  @override
  State<MyPackagesScreen> createState() => _MyPackagesScreenState();
}

class _MyPackagesScreenState extends State<MyPackagesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  final Map<String, Map<String, dynamic>?> _pp = {}; // provider id -> provider_profiles

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      _items = List<Map<String, dynamic>>.from(await supabase.rpc('my_packages') as List);
      for (final p in _items) {
        final id = p['provider_id'] as String;
        if (!_pp.containsKey(id)) {
          _pp[id] = await supabase.from('provider_profiles').select().eq('provider_id', id).maybeSingle();
        }
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _paid(Map<String, dynamic> p) async {
    final methods = payMethodsOf(_pp[p['provider_id']]);
    final method = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('How did you pay ${(p['pro_name'] ?? '').toString().split(' ').first}?',
                style: TextStyle(fontFamily: AppTheme.displayFamily, fontSize: 21, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const SizedBox(height: 6),
            for (final m in methods)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(m.icon),
                title: Text(m.label),
                subtitle: m.account == null ? null : Text('To ${m.displayAccount}${m.accountName != null ? ' (${m.accountName})' : ''}'),
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ]),
        ),
      ),
    );
    if (method == null) return;
    try {
      await supabase.rpc('claim_package_payment', params: {'p_member': p['member_id'], 'p_method': method});
      Haptics.firm();
      if (mounted) _toast(context, 'Thanks! ${(p['pro_name'] ?? 'Your pro').toString().split(' ').first} will confirm it soon.');
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    }
  }

  Future<void> _cancel(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cancel ${p['name']}?'),
        content: const Text('You won\'t be asked to pay for next month. Visits already paid for this month can still be booked.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep it')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel package'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await supabase.rpc('cancel_package', params: {'p_member': p['member_id']});
      Haptics.warn();
      _load();
    } on PostgrestException catch (e) {
      if (mounted) _toast(context, e.message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My packages')),
      body: _loading
          ? const LoadingPlaceholder()
          : RefreshIndicator.adaptive(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
                Text('Visits you\'ve paid for, with your pros.', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                const SizedBox(height: 14),
                if (_items.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(children: [
                      const EmptyState(
                        icon: TablerIcons.calendar_repeat,
                        title: 'No packages yet',
                        message: 'Some pros offer a monthly price for regular visits. Look for "Monthly packages" on their profile.',
                      ),
                      FilledButton.icon(
                        onPressed: () => context.go('/browse'),
                        icon: const Icon(TablerIcons.search),
                        label: const Text('Find a beauty pro'),
                      ),
                    ]),
                  ),
                for (final p in _items) ...[
                  _MyPackageCard(p: p, onPaid: () => _paid(p), onCancel: () => _cancel(p)),
                  const SizedBox(height: 12),
                ],
              ]),
            ),
    );
  }
}

class _MyPackageCard extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback onPaid;
  final VoidCallback onCancel;
  const _MyPackageCard({required this.p, required this.onPaid, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
    final items = List<Map<String, dynamic>>.from(p['items'] as List? ?? const []);
    final included = items.fold<int>(0, (s, i) => s + ((i['included'] as num?) ?? 0).toInt());
    final used = items.fold<int>(0, (s, i) => s + ((i['used'] as num?) ?? 0).toInt());
    final status = p['pay_status'] as String? ?? 'unpaid';
    final active = p['status'] == 'active';
    final month = DateTime.tryParse((p['month'] ?? '').toString());
    final monthName = month == null ? 'this month' : months[month.month - 1];
    final next = month == null ? null : DateTime(month.year, month.month + 1, 1);
    final first = (p['pro_name'] ?? '').toString().split(' ').first;
    final price = pkgMoney((p['price'] as num?) ?? 0);
    final nextItem = items.where((i) => ((i['used'] as num?) ?? 0) < ((i['included'] as num?) ?? 0)).firstOrNull;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.card, borderRadius: BorderRadius.circular(24), boxShadow: _shadow),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          PersonAvatar(name: p['pro_name'] ?? '', url: p['pro_avatar'] as String?, size: 48),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${p['name']} · $first', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text('$price a month · $monthName', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
            ]),
          ),
          if (!active)
            _pill('Cancelled', AppColors.textSecondary)
          else if (status == 'paid')
            _pill('Paid', _green)
          else if (status == 'claimed')
            _pill('Checking', AppColors.goldText)
          else
            _pill('Pay for ${monthName.substring(0, 3)}', AppColors.goldText),
        ]),
        if (status == 'paid') ...[
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final i in items)
              for (var k = 0; k < ((i['included'] as num?) ?? 0).toInt(); k++)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: k < ((i['used'] as num?) ?? 0) ? _green.withValues(alpha: 0.12) : AppColors.surfaceMuted,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                      '${k < ((i['used'] as num?) ?? 0) ? '✓ ' : ''}${i['service_name']}',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: k < ((i['used'] as num?) ?? 0) ? _green : AppColors.textPrimary)),
                ),
          ]),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: included == 0 ? 0 : used / included,
              minHeight: 8,
              backgroundColor: AppColors.surfaceMuted,
              color: AppColors.gold,
            ),
          ),
          const SizedBox(height: 6),
          Text('$used of $included visits used${active && next != null ? ' · renews 1 ${months[next.month - 1].substring(0, 3)}' : ''}',
              style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ] else if (status == 'claimed')
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('You said you sent $price. Your visits unlock as soon as $first confirms.',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          )
        else if (active)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text('Send $first $price to unlock $monthName\'s $included ${included == 1 ? 'visit' : 'visits'}, then tap "I\'ve paid".',
                style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
          ),
        const SizedBox(height: 12),
        Row(children: [
          if (active)
            SizedBox(
              height: 44,
              child: OutlinedButton(
                onPressed: onCancel,
                style: OutlinedButton.styleFrom(shape: const StadiumBorder(), padding: const EdgeInsets.symmetric(horizontal: 18)),
                child: const Text('Cancel'),
              ),
            ),
          if (active) const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 44,
              child: status == 'paid'
                  ? FilledButton(
                      onPressed: nextItem == null
                          ? null
                          : () => context.push('/book/${p['provider_id']}/${nextItem['service_id']}?package=1'),
                      style: FilledButton.styleFrom(shape: const StadiumBorder()),
                      child: Text(nextItem == null ? 'All visits used' : 'Book a visit · \$0',
                          overflow: TextOverflow.ellipsis),
                    )
                  : status == 'claimed' || !active
                      ? OutlinedButton(
                          onPressed: () => context.push('/provider/${p['provider_id']}'),
                          style: OutlinedButton.styleFrom(shape: const StadiumBorder()),
                          child: Text('View $first\'s profile'),
                        )
                      : FilledButton(
                          onPressed: onPaid,
                          style: FilledButton.styleFrom(shape: const StadiumBorder()),
                          child: Text('I\'ve paid $first $price'),
                        ),
            ),
          ),
        ]),
      ]),
    );
  }
}
