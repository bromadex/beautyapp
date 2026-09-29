import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;

import '../services/fee_checkout.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/pay_methods.dart';
import '../widgets/ui.dart';

/// A pro's product ads. Advertising only: clients contact the pro to buy.
/// 3 listings are free; $5 adds 20 more for 30 days.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
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
        supabase
            .from('products')
            .select()
            .eq('provider_id', supabase.auth.currentUser!.id)
            .order('created_at', ascending: false),
        supabase.rpc('my_products_plan'),
      ]);
      if (mounted) {
        setState(() {
          _products = List<Map<String, dynamic>>.from(res[0] as List);
          _plan = Map<String, dynamic>.from(res[1] as Map);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _allowance => (_plan['allowance'] as num?)?.toInt() ?? 3;
  int get _active => (_plan['active'] as num?)?.toInt() ?? 0;

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _buyPack({bool large = false}) async {
    final outcome = await FeeCheckout.run(context, BeauTapFee('product_pack', large ? 'large' : null));
    if (outcome == FeeOutcome.cancelled) return;
    await _load();
    _toast(outcome == FeeOutcome.paid
        ? '${large ? 50 : 20} more listings added for 30 days'
        : 'Thanks! We\'ll add your listings as soon as we see your EcoCash payment.');
  }

  DateTime? _boostedUntil(Map p) {
    final d = DateTime.tryParse((p['boosted_until'] ?? '').toString())?.toLocal();
    return d != null && d.isAfter(DateTime.now()) ? d : null;
  }

  Future<void> _boost(Map<String, dynamic> p) async {
    if (p['is_active'] != true) {
      _toast('Show this product first, then boost it', error: true);
      return;
    }
    final outcome = await FeeCheckout.run(context, BeauTapFee('product_boost', null, p['id'] as String));
    if (outcome == FeeOutcome.cancelled) return;
    await _load();
    _toast(outcome == FeeOutcome.paid
        ? '${p['name']} is at the top of Home for 7 days'
        : 'Thanks! We\'ll boost it as soon as we see your EcoCash payment.');
  }

  Future<void> _toggle(Map<String, dynamic> p, bool on) async {
    try {
      await supabase.from('products').update({'is_active': on}).eq('id', p['id']);
      await _load();
    } on PostgrestException catch (e) {
      _toast(e.message, error: true);
    }
  }

  Future<void> _delete(Map<String, dynamic> p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this product?'),
        content: Text(p['name'] ?? ''),
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
    final saved = await showModalBottomSheet<bool>(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProductSheet(product: p),
    );
    if (saved == true) await _load();
  }

  @override
  Widget build(BuildContext context) {
    final packs = List<Map<String, dynamic>>.from(_plan['packs'] as List? ?? const []);
    final packEnds = packs.isEmpty ? null : DateTime.tryParse(packs.last['expires_at'] ?? '')?.toLocal();
    final full = _active >= _allowance;
    return Scaffold(
      appBar: AppBar(title: const Text('Products')),
      floatingActionButton: _loading
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _edit(),
              icon: const Icon(TablerIcons.plus),
              label: const Text('Add product'),
            ),
      body: _loading
          ? const LoadingPlaceholder()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: AppColors.forest, borderRadius: AppRadius.xlAll),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text('$_active of $_allowance',
                          style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      const Text('listings showing', style: TextStyle(color: AppColors.goldLight)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: AppRadius.pill,
                      child: LinearProgressIndicator(
                        value: _allowance == 0 ? 0 : (_active / _allowance).clamp(0, 1).toDouble(),
                        minHeight: 8,
                        backgroundColor: AppColors.primaryDark,
                        color: AppColors.gold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      packEnds != null
                          ? '3 free + ${_allowance - 3} from packs. Your pack ends ${packEnds.day}/${packEnds.month}.'
                          : '3 listings are free. Add more for 30 days: 20 for \$5 or 50 for \$10.',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.gold, foregroundColor: AppColors.primaryDark, padding: EdgeInsets.zero),
                          onPressed: () => _buyPack(),
                          child: const Text('+20 · \$5'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                              backgroundColor: AppColors.gold, foregroundColor: AppColors.primaryDark, padding: EdgeInsets.zero),
                          onPressed: () => _buyPack(large: true),
                          child: const Text('+50 · \$10'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Text('Boost a product for \$1 to put it at the top of clients\' Home screen for 7 days. '
                        'Use the ⋮ menu on a product.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 12.5)),
                  ]),
                ),
                const SizedBox(height: 10),
                Text(
                  'Advertising only: clients message you on WhatsApp to buy. Medical products, like skin '
                  'lightening creams or injectables, aren\'t allowed.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 16),
                if (_products.isEmpty)
                  const EmptyState(
                    icon: TablerIcons.shopping_bag,
                    title: 'No products yet',
                    message: 'Show clients the hair, nail and skin products you sell.',
                  )
                else
                  for (final p in _products)
                    Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Row(children: [
                          ClipRRect(
                            borderRadius: AppRadius.smAll,
                            child: SizedBox(
                              width: 64,
                              height: 64,
                              child: (p['image_url'] ?? '').toString().isEmpty
                                  ? Container(
                                      color: AppColors.primarySoft,
                                      child: Icon(TablerIcons.shopping_bag, color: AppColors.primary))
                                  : Image.network(p['image_url'], fit: BoxFit.cover),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => _edit(p),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(p['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.w800)),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (p['price'] != null) '\$${amountText(p['price'] as num)}',
                                    p['is_active'] == true ? 'Showing' : 'Hidden',
                                    if (_boostedUntil(p) != null)
                                      'Boosted to ${_boostedUntil(p)!.day}/${_boostedUntil(p)!.month}',
                                  ].join(' · '),
                                  style: TextStyle(
                                      fontSize: 13,
                                      color: p['is_active'] == true ? AppColors.textSecondary : AppColors.warningText),
                                ),
                              ]),
                            ),
                          ),
                          Switch(
                            value: p['is_active'] == true,
                            onChanged: (v) {
                              if (v && full) {
                                _toast('You\'re using all $_allowance listings. Hide one or add 20 more for \$5.',
                                    error: true);
                                return;
                              }
                              _toggle(p, v);
                            },
                          ),
                          PopupMenuButton<String>(
                            onSelected: (v) => switch (v) { 'edit' => _edit(p), 'boost' => _boost(p), _ => _delete(p) },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'boost', child: Text('Boost for \$1 · 7 days')),
                              PopupMenuItem(value: 'edit', child: Text('Edit')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ]),
                      ),
                    ),
              ]),
            ),
    );
  }
}

class _ProductSheet extends StatefulWidget {
  final Map<String, dynamic>? product;
  const _ProductSheet({this.product});

  @override
  State<_ProductSheet> createState() => _ProductSheetState();
}

class _ProductSheetState extends State<_ProductSheet> {
  late final _name = TextEditingController(text: widget.product?['name'] ?? '');
  late final _price = TextEditingController(
      text: widget.product?['price'] == null ? '' : amountText(widget.product!['price'] as num));
  late final _desc = TextEditingController(text: widget.product?['description'] ?? '');
  late String? _imageUrl = widget.product?['image_url'];
  Uint8List? _newImage;
  String _imageType = 'image/jpeg';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    final x = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1200);
    if (x == null) return;
    final bytes = await x.readAsBytes();
    final t = x.mimeType ?? 'image/jpeg';
    setState(() {
      _newImage = bytes;
      _imageType = const ['image/png', 'image/webp'].contains(t) ? t : 'image/jpeg';
    });
  }

  Future<void> _save() async {
    if (_name.text.trim().length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Give the product a name')));
      return;
    }
    final price = _price.text.trim().isEmpty ? null : double.tryParse(_price.text.trim());
    setState(() => _saving = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      if (_newImage != null) {
        final path = '$uid/${DateTime.now().millisecondsSinceEpoch}.${_imageType.split('/').last.replaceAll('jpeg', 'jpg')}';
        await supabase.storage
            .from('products')
            .uploadBinary(path, _newImage!, fileOptions: FileOptions(contentType: _imageType));
        _imageUrl = supabase.storage.from('products').getPublicUrl(path);
      }
      final row = {
        'name': _name.text.trim(),
        'price': price,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'image_url': _imageUrl,
      };
      if (widget.product == null) {
        await supabase.from('products').insert({...row, 'provider_id': uid});
      } else {
        await supabase.from('products').update(row).eq('id', widget.product!['id']);
      }
      if (mounted) Navigator.pop(context, true);
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Could not save. Try again.'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.product == null ? 'Add product' : 'Edit product', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          InkWell(
            onTap: _pick,
            borderRadius: AppRadius.mdAll,
            child: Container(
              height: 140,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: AppColors.primarySoft,
                borderRadius: AppRadius.mdAll,
              ),
              child: _newImage != null
                  ? Image.memory(_newImage!, fit: BoxFit.cover)
                  : (_imageUrl ?? '').isNotEmpty
                      ? Image.network(_imageUrl!, fit: BoxFit.cover)
                      : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(TablerIcons.photo_plus, color: AppColors.primary, size: 28),
                          SizedBox(height: 6),
                          Text('Add a photo', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700)),
                        ]),
            ),
          ),
          const SizedBox(height: 12),
          TextField(controller: _name, maxLength: 60, decoration: const InputDecoration(labelText: 'Name')),
          TextField(
            controller: _price,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
            decoration: const InputDecoration(labelText: 'Price in \$ (optional)', prefixText: '\$ '),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            maxLength: 300,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        ]),
      ),
    );
  }
}
