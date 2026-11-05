import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;

import '../glass.dart';
import '../services/fee_checkout.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../utils/pay_methods.dart';
import '../widgets/shop_bits.dart';
import '../widgets/ui.dart';
import 'orders_screen.dart';

/// A pro's shop: the items they sell, orders for them, and how they sell.
class ProductsScreen extends StatefulWidget {
  final int initialTab;
  const ProductsScreen({super.key, this.initialTab = 0});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  int _waiting = 0;

  @override
  void initState() {
    super.initState();
    _counts();
  }

  Future<void> _counts() async {
    try {
      final c = await supabase.rpc('my_order_counts');
      if (mounted) setState(() => _waiting = ((c as Map)['selling'] as num?)?.toInt() ?? 0);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      initialIndex: widget.initialTab,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('My shop'),
          actions: [
            TextButton.icon(
              onPressed: () => context.push('/market'),
              icon: const Icon(TablerIcons.building_store, size: 18),
              label: const Text('View shop'),
            ),
            const SizedBox(width: 4),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Items'),
            Tab(
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Text('Orders'),
                if (_waiting > 0) ...[
                  const SizedBox(width: 6),
                  Badge(label: Text('$_waiting'), backgroundColor: AppColors.gold, textColor: Colors.black),
                ],
              ]),
            ),
            const Tab(text: 'Settings'),
          ]),
        ),
        body: const TabBarView(children: [
          _ItemsTab(),
          OrdersList(role: 'selling'),
          _ShopSettingsTab(),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Items
// ---------------------------------------------------------------------

class _ItemsTab extends StatefulWidget {
  const _ItemsTab();

  @override
  State<_ItemsTab> createState() => _ItemsTabState();
}

class _ItemsTabState extends State<_ItemsTab> {
  bool _loading = true;
  List<Map<String, dynamic>> _products = [];
  Map<String, dynamic> _plan = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<dynamic>([
        supabase.from('products').select().eq('provider_id', myId!).order('created_at', ascending: false),
        supabase.rpc('my_products_plan'),
      ]);
      _products = List<Map<String, dynamic>>.from(res[0] as List);
      _plan = Map<String, dynamic>.from(res[1] as Map);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  int get _allowance => (_plan['allowance'] as num?)?.toInt() ?? 3;
  int get _active => (_plan['active'] as num?)?.toInt() ?? 0;

  Future<void> _buyPack({bool large = false}) async {
    final outcome = await FeeCheckout.run(context, BeauTapFee('product_pack', large ? 'large' : null));
    if (outcome == FeeOutcome.cancelled || !mounted) return;
    await _load();
    if (!mounted) return;
    shopToast(
        context,
        outcome == FeeOutcome.paid
            ? '${large ? 50 : 20} more listings added for 30 days'
            : 'Thanks! We\'ll add your listings as soon as we see your EcoCash payment.');
  }

  DateTime? _boostedUntil(Map p) {
    final d = DateTime.tryParse((p['boosted_until'] ?? '').toString())?.toLocal();
    return d != null && d.isAfter(DateTime.now()) ? d : null;
  }

  Future<void> _boost(Map<String, dynamic> p) async {
    if (p['is_active'] != true) {
      shopToast(context, 'Show this item in the shop first, then boost it', error: true);
      return;
    }
    final outcome = await FeeCheckout.run(context, BeauTapFee('product_boost', null, p['id'] as String));
    if (outcome == FeeOutcome.cancelled || !mounted) return;
    await _load();
    if (!mounted) return;
    shopToast(
        context,
        outcome == FeeOutcome.paid
            ? '${p['name']} is featured at the top of the shop and Home for 7 days'
            : 'Thanks! We\'ll boost it as soon as we see your EcoCash payment.');
  }

  Future<void> _toggle(Map<String, dynamic> p, bool on) async {
    try {
      await supabase.from('products').update({'is_active': on}).eq('id', p['id']);
      Haptics.light();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) shopToast(context, e.message, error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this item?'),
        content: Text('${p['name'] ?? ''}\n\nPast orders keep their details.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await supabase.from('products').delete().eq('id', p['id']);
    await _load();
  }

  Future<void> _edit([Map<String, dynamic>? p]) async {
    final saved = await context.push<bool>(p == null ? '/provider/shop/item/new' : '/provider/shop/item/${p['id']}');
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingPlaceholder();
    final packs = List<Map<String, dynamic>>.from(_plan['packs'] as List? ?? const []);
    final packEnds = packs.isEmpty ? null : DateTime.tryParse(packs.last['expires_at'] ?? '')?.toLocal();
    final full = _active >= _allowance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(),
        icon: const Icon(TablerIcons.plus),
        label: const Text('Add item'),
      ),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: Glass.hero(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text('$_active of $_allowance',
                    style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800)),
                const SizedBox(width: 8),
                const Text('items in the shop', style: TextStyle(color: AppColors.goldLight)),
              ]),
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: AppRadius.pill,
                child: LinearProgressIndicator(
                  value: _allowance == 0 ? 0 : (_active / _allowance).clamp(0, 1).toDouble(),
                  minHeight: 6,
                  backgroundColor: AppColors.primaryDark,
                  color: AppColors.gold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                packEnds != null
                    ? '3 free + ${_allowance - 3} from packs, until ${packEnds.day}/${packEnds.month}. '
                    : '3 items are free. Need more? 20 for \$5 or 50 for \$10, for 30 days. ',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
              ),
              const SizedBox(height: 10),
              Row(children: [
                for (final large in [false, true]) ...[
                  if (large) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                          backgroundColor: AppColors.gold,
                          foregroundColor: Colors.black,
                          minimumSize: const Size(0, 40),
                          padding: EdgeInsets.zero),
                      onPressed: () => _buyPack(large: large),
                      child: Text(large ? '+50 · \$10' : '+20 · \$5'),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            'Buyers order in the app and pay you directly; BeauTap takes no cut. Boost an item for \$1 to feature it for 7 days. '
            'Medical products, like skin lightening creams or injectables, aren\'t allowed.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (_products.isEmpty)
            EmptyState(
              icon: TablerIcons.shopping_bag,
              title: 'Nothing for sale yet',
              message: 'Add the hair, nail and skin products you sell. Everyone on BeauTap can buy them.',
              actionLabel: 'Add your first item',
              onAction: () => _edit(),
            )
          else
            for (final p in _products) _row(p, full),
        ]),
      ),
    );
  }

  Widget _row(Map<String, dynamic> p, bool full) {
    final imgs = (p['images'] as List?) ?? const [];
    final img = imgs.isNotEmpty ? imgs.first.toString() : p['image_url'] as String?;
    final stock = p['stock_qty'] as num?;
    final out = p['in_stock'] == false || (stock != null && stock <= 0);
    final boosted = _boostedUntil(p);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppColors.card,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          borderRadius: AppRadius.mdAll,
          onTap: () => _edit(p),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
            child: Row(children: [
              SizedBox(width: 64, height: 64, child: ProductImage(img, radius: AppRadius.smAll)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    [
                      money(p['price'] as num?),
                      out ? 'Sold out' : (stock != null ? '$stock in stock' : 'In stock'),
                      if (imgs.length > 1) '${imgs.length} photos',
                    ].join(' · '),
                    style: TextStyle(fontSize: 13, color: out ? AppColors.warningText : AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Row(children: [
                    statusChip(p['is_active'] == true ? 'In the shop' : 'Hidden',
                        p['is_active'] == true ? AppColors.success : AppColors.textSecondary),
                    if (boosted != null) ...[
                      const SizedBox(width: 6),
                      statusChip('Featured to ${boosted.day}/${boosted.month}', AppColors.goldText),
                    ],
                  ]),
                ]),
              ),
              Switch.adaptive(
                value: p['is_active'] == true,
                onChanged: (v) {
                  if (v && full) {
                    shopToast(context, 'You\'re using all $_allowance listings. Hide one or add 20 more for \$5.', error: true);
                    return;
                  }
                  _toggle(p, v);
                },
              ),
              PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'edit' => _edit(p),
                  'boost' => _boost(p),
                  'view' => context.push('/shop/item/${p['id']}'),
                  _ => _delete(p),
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'view', child: Text('See it as buyers do')),
                  PopupMenuItem(value: 'boost', child: Text('Feature for \$1 · 7 days')),
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------
// Settings: how this shop sells
// ---------------------------------------------------------------------

class _ShopSettingsTab extends StatefulWidget {
  const _ShopSettingsTab();

  @override
  State<_ShopSettingsTab> createState() => _ShopSettingsTabState();
}

class _ShopSettingsTabState extends State<_ShopSettingsTab> {
  bool _loading = true;
  bool _saving = false;
  bool _accepts = true, _collect = true, _deliver = false, _post = false, _appt = true;
  final _fee = TextEditingController();
  final _note = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _fee.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await supabase.from('shop_settings').select().eq('provider_id', myId!).maybeSingle();
      if (s != null) {
        _accepts = s['accepts_orders'] != false;
        _collect = s['can_collect'] != false;
        _deliver = s['can_deliver'] == true;
        _post = s['can_post'] == true;
        _appt = s['at_appointment'] != false;
        _fee.text = s['delivery_fee'] == null ? '' : amountText(s['delivery_fee'] as num);
        _note.text = s['note'] ?? '';
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_collect && !_deliver && !_post && !_appt) {
      shopToast(context, 'Choose at least one way buyers can get their items', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await supabase.from('shop_settings').upsert({
        'provider_id': myId,
        'accepts_orders': _accepts,
        'can_collect': _collect,
        'can_deliver': _deliver,
        'delivery_fee': _deliver ? double.tryParse(_fee.text.trim()) : null,
        'can_post': _post,
        'at_appointment': _appt,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      });
      Haptics.firm();
      if (mounted) shopToast(context, 'Shop settings saved');
    } on PostgrestException catch (e) {
      if (mounted) shopToast(context, e.message, error: true);
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const LoadingPlaceholder();
    Widget sw(String t, String? sub, bool v, ValueChanged<bool> f, {IconData? icon}) => SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.symmetric(horizontal: 14),
          secondary: icon == null ? null : Icon(icon, color: AppColors.textSecondary),
          title: Text(t, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: sub == null ? null : Text(sub),
          value: v,
          onChanged: (x) => setState(() => f(x)),
        );
    Widget card(List<Widget> c) => Container(
          decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.mdAll),
          child: Column(children: c),
        );
    return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 40), children: [
      sectionLabel('Orders'),
      card([
        sw('Taking orders', _accepts ? 'Buyers can order your items' : 'Your items show, but buyers can\'t order for now',
            _accepts, (x) => _accepts = x),
      ]),
      sectionLabel('How buyers can get their items'),
      card([
        sw('Collect from me', null, _collect, (x) => _collect = x, icon: TablerIcons.building_store),
        Divider(height: 1, color: AppColors.border),
        sw('At their appointment', 'Hand it over when they come in', _appt, (x) => _appt = x, icon: TablerIcons.calendar_event),
        Divider(height: 1, color: AppColors.border),
        sw('I deliver', null, _deliver, (x) => _deliver = x, icon: TablerIcons.truck_delivery),
        if (_deliver)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: TextField(
              controller: _fee,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
              decoration: const InputDecoration(labelText: 'Usual delivery fee', prefixText: '\$ ', helperText: 'You can change it per order'),
            ),
          ),
        Divider(height: 1, color: AppColors.border),
        sw('Courier / post', 'For buyers in other towns', _post, (x) => _post = x, icon: TablerIcons.package),
      ]),
      sectionLabel('Note for buyers'),
      TextField(
        controller: _note,
        maxLength: 200,
        maxLines: 2,
        decoration: const InputDecoration(hintText: 'e.g. Collect at my salon, Mon to Sat 9 to 5'),
      ),
      const SizedBox(height: 8),
      Text('Buyers pay you with the payment methods on your profile. You confirm each order\'s terms in its chat.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      const SizedBox(height: 16),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        onPressed: _saving ? null : _save,
        child: Text(_saving ? 'Saving…' : 'Save'),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------
// Add or edit an item
// ---------------------------------------------------------------------

class _Photo {
  final String? url;
  final Uint8List? bytes;
  final String type;
  const _Photo({this.url, this.bytes, this.type = 'image/jpeg'});
}

class ProductEditScreen extends StatefulWidget {
  final String? productId;
  const ProductEditScreen({super.key, this.productId});

  @override
  State<ProductEditScreen> createState() => _ProductEditScreenState();
}

class _ProductEditScreenState extends State<ProductEditScreen> {
  final _name = TextEditingController();
  final _price = TextEditingController();
  final _desc = TextEditingController();
  final _qty = TextEditingController();
  String _category = 'Hair';
  bool _trackStock = false;
  bool _inStock = true;
  bool _active = true;
  List<_Photo> _photos = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
    for (final c in [_name, _price, _desc]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _desc, _qty]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    if (widget.productId != null) {
      try {
        final p = await supabase.from('products').select().eq('id', widget.productId!).single();
        _name.text = p['name'] ?? '';
        _price.text = p['price'] == null ? '' : amountText(p['price'] as num);
        _desc.text = p['description'] ?? '';
        _category = shopCategories.contains(p['category']) ? p['category'] : 'Other';
        _trackStock = p['stock_qty'] != null;
        _qty.text = p['stock_qty']?.toString() ?? '';
        _inStock = p['in_stock'] != false;
        _active = p['is_active'] == true;
        final imgs = ((p['images'] as List?) ?? const []).map((e) => e.toString()).toList();
        if (imgs.isEmpty && (p['image_url'] ?? '').toString().isNotEmpty) imgs.add(p['image_url']);
        _photos = [for (final u in imgs) _Photo(url: u)];
      } catch (_) {}
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pick() async {
    final left = 5 - _photos.length;
    if (left <= 0) return;
    final xs = await ImagePicker().pickMultiImage(imageQuality: 80, maxWidth: 1400, limit: left);
    for (final x in xs.take(left)) {
      final t = x.mimeType ?? 'image/jpeg';
      _photos.add(_Photo(bytes: await x.readAsBytes(), type: const ['image/png', 'image/webp'].contains(t) ? t : 'image/jpeg'));
    }
    if (mounted) setState(() {});
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      shopToast(context, 'Give the item a name', error: true);
      return;
    }
    final price = double.tryParse(_price.text.trim());
    if (price == null || price <= 0) {
      shopToast(context, 'Add a price so buyers can order it', error: true);
      return;
    }
    final qty = _trackStock ? int.tryParse(_qty.text.trim()) : null;
    if (_trackStock && qty == null) {
      shopToast(context, 'How many do you have?', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = myId!;
      final urls = <String>[];
      var i = 0;
      for (final ph in _photos) {
        if (ph.url != null) {
          urls.add(ph.url!);
        } else {
          final path = '$uid/${DateTime.now().millisecondsSinceEpoch}_${i++}.${ph.type.split('/').last.replaceAll('jpeg', 'jpg')}';
          await supabase.storage.from('products').uploadBinary(path, ph.bytes!, fileOptions: FileOptions(contentType: ph.type));
          urls.add(supabase.storage.from('products').getPublicUrl(path));
        }
      }
      final row = {
        'name': _name.text.trim(),
        'price': price,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'category': _category,
        'images': urls,
        'image_url': urls.isEmpty ? null : urls.first,
        'stock_qty': qty,
        'in_stock': _trackStock ? (qty ?? 0) > 0 : _inStock,
        'is_active': _active,
      };
      if (widget.productId == null) {
        await supabase.from('products').insert({...row, 'provider_id': uid});
      } else {
        await supabase.from('products').update(row).eq('id', widget.productId!);
      }
      Haptics.firm();
      if (mounted) context.pop(true);
    } on PostgrestException catch (e) {
      if (mounted) shopToast(context, e.message, error: true);
    } catch (_) {
      if (mounted) shopToast(context, 'Could not save. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _thumb(_Photo ph, int i) {
    final img = ph.bytes != null ? Image.memory(ph.bytes!, fit: BoxFit.cover) : Image.network(ph.url!, fit: BoxFit.cover);
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(children: [
        Positioned.fill(child: ClipRRect(borderRadius: AppRadius.mdAll, child: img)),
        if (i == 0)
          Positioned(
            left: 6,
            bottom: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: AppRadius.pill),
              child: const Text('Cover', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ),
        Positioned(
          right: 4,
          top: 4,
          child: Row(children: [
            if (i > 0)
              _mini(TablerIcons.star, () => setState(() => _photos.insert(0, _photos.removeAt(i)))),
            const SizedBox(width: 4),
            _mini(TablerIcons.x, () => setState(() => _photos.removeAt(i))),
          ]),
        ),
      ]),
    );
  }

  Widget _mini(IconData i, VoidCallback f) => InkWell(
        onTap: f,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), shape: BoxShape.circle),
          child: Icon(i, size: 14, color: Colors.white),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final preview = {
      'id': 'preview',
      'name': _name.text.trim().isEmpty ? 'Item name' : _name.text.trim(),
      'price': double.tryParse(_price.text.trim()),
      'images': [if (_photos.isNotEmpty && _photos.first.url != null) _photos.first.url],
      'in_stock': _trackStock ? (int.tryParse(_qty.text) ?? 0) > 0 : _inStock,
      'stock_qty': _trackStock ? int.tryParse(_qty.text) : null,
    };
    return Scaffold(
      appBar: AppBar(title: Text(widget.productId == null ? 'Add item' : 'Edit item')),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _saving || _loading ? null : _save,
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ),
      ),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              sectionLabel('Photos · ${_photos.length} of 5', trailing: Text('First is the cover', style: TextStyle(fontSize: 12, color: AppColors.textTertiary))),
              SizedBox(
                height: 96,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (var i = 0; i < _photos.length; i++) Padding(padding: const EdgeInsets.only(right: 8), child: _thumb(_photos[i], i)),
                  if (_photos.length < 5)
                    InkWell(
                      onTap: _pick,
                      borderRadius: AppRadius.mdAll,
                      child: Container(
                        width: 96,
                        decoration: BoxDecoration(
                          color: AppColors.primarySoft,
                          borderRadius: AppRadius.mdAll,
                          border: Border.all(color: AppColors.gold.withValues(alpha: 0.5)),
                        ),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(TablerIcons.photo_plus, color: AppColors.primary),
                          const SizedBox(height: 4),
                          Text('Add', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ]),
                      ),
                    ),
                ]),
              ),
              sectionLabel('Details'),
              TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Brazilian body wave wig, 18"')),
              const SizedBox(height: 4),
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: const InputDecoration(labelText: 'Price', prefixText: '\$ ', helperText: 'Buyers can offer a different price; you decide'),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _desc,
                maxLength: 1000,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What it is, size or length, colour, how to use it, what\'s included',
                  alignLabelWithHint: true,
                ),
              ),
              sectionLabel('Category'),
              ChoiceRow<String>(
                options: shopCategories,
                value: _category,
                label: (c) => c,
                icon: shopCategoryIcon,
                onChanged: (c) => setState(() => _category = c),
              ),
              sectionLabel('Stock'),
              Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.mdAll),
                child: Column(children: [
                  SwitchListTile.adaptive(
                    title: const Text('Count my stock', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('It goes down when you confirm payment, and shows sold out at 0'),
                    value: _trackStock,
                    onChanged: (v) => setState(() => _trackStock = v),
                  ),
                  if (_trackStock)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: TextField(
                        controller: _qty,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'How many you have'),
                      ),
                    )
                  else ...[
                    Divider(height: 1, color: AppColors.border),
                    SwitchListTile.adaptive(
                      title: const Text('In stock', style: TextStyle(fontWeight: FontWeight.w600)),
                      value: _inStock,
                      onChanged: (v) => setState(() => _inStock = v),
                    ),
                  ],
                ]),
              ),
              sectionLabel('Visibility'),
              Container(
                decoration: BoxDecoration(color: AppColors.card, borderRadius: AppRadius.mdAll),
                child: SwitchListTile.adaptive(
                  title: const Text('Show in the shop', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('Hidden items only you can see'),
                  value: _active,
                  onChanged: (v) => setState(() => _active = v),
                ),
              ),
              sectionLabel('How buyers see it'),
              Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: 190,
                  child: IgnorePointer(
                    child: _photos.isNotEmpty && _photos.first.bytes != null
                        ? Stack(children: [
                            ProductTile(p: preview, onTap: () {}, showSeller: false),
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: AspectRatio(
                                aspectRatio: 1,
                                child: ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                                  child: Image.memory(_photos.first.bytes!, fit: BoxFit.cover),
                                ),
                              ),
                            ),
                          ])
                        : ProductTile(p: preview, onTap: () {}, showSeller: false),
                  ),
                ),
              ),
            ]),
    );
  }
}
