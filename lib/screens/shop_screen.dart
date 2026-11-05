import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/cart.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../widgets/booking_bits.dart' show payBrand;
import '../utils/pay_methods.dart' show payMethodLabel;
import '../widgets/shop_bits.dart';
import '../widgets/ui.dart';

// =====================================================================
// The shop: everyone can browse. Clients and pros can buy, but not
// their own items.
// =====================================================================

class ShopScreen extends StatefulWidget {
  /// True inside the client tab bar (large title, no back button).
  final bool asTab;
  const ShopScreen({super.key, this.asTab = false});

  @override
  State<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends State<ShopScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  String? _category;
  String _sort = 'new';
  String? _city;
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    Cart.instance.load();
    _init();
  }

  Future<void> _init() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final c = sp.getString('selected_city');
      if (c != null && c != 'All Zimbabwe') _city = c;
    } catch (_) {}
    await _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final q = _search.text.trim();
      final res = await supabase.rpc('shop_items', params: {
        'p_city': _city,
        'p_category': _category,
        'p_q': q.isEmpty ? null : q,
        'p_sort': _sort,
        'p_limit': 60,
      });
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  void _onSearch(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _load);
  }

  void _open(Map<String, dynamic> p) => context.push('/shop/item/${p['id']}');

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (isSignedIn)
        IconButton(
          tooltip: 'My orders',
          onPressed: () => context.push('/orders'),
          icon: const Icon(TablerIcons.receipt),
        ),
      CartButton(onTap: () => context.push('/cart')),
      const SizedBox(width: 4),
    ];
    final sortLabel = switch (_sort) {
      'price_low' => 'Lowest price',
      'price_high' => 'Highest price',
      'popular' => 'Popular',
      _ => 'Newest',
    };
    return Scaffold(
      appBar: widget.asTab
          ? largeTitleBar(context, 'Shop', actions: actions)
          : AppBar(title: const Text('Shop'), actions: actions),
      body: RefreshIndicator.adaptive(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(0, 4, 0, widget.asTab ? tabBarSpace(context) + 80 : 32),
          children: [
            PageWidth(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextField(
                    controller: _search,
                    onChanged: _onSearch,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search hair, wigs, skin care…',
                      prefixIcon: const Icon(TablerIcons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(TablerIcons.x, size: 18),
                              onPressed: () {
                                _search.clear();
                                _load();
                                setState(() {});
                              }),
                    ),
                  ),
                  const SizedBox(height: 12),
                ]),
              ),
            ),
            SizedBox(
              height: 40,
              child: PageWidth(
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final c in [null, ...shopCategories])
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          showCheckmark: false,
                          avatar: c == null ? null : Icon(shopCategoryIcon(c), size: 16),
                          label: Text(c ?? 'All'),
                          selected: _category == c,
                          onSelected: (_) {
                            Haptics.light();
                            setState(() => _category = c);
                            _load();
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
            PageWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      _loading
                          ? 'Loading…'
                          : '${_items.length} item${_items.length == 1 ? '' : 's'}'
                              '${_city != null ? ' · $_city first' : ''}',
                      style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                    ),
                  ),
                  PopupMenuButton<String>(
                    initialValue: _sort,
                    onSelected: (v) {
                      setState(() => _sort = v);
                      _load();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'new', child: Text('Newest')),
                      PopupMenuItem(value: 'popular', child: Text('Popular')),
                      PopupMenuItem(value: 'price_low', child: Text('Lowest price')),
                      PopupMenuItem(value: 'price_high', child: Text('Highest price')),
                    ],
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(TablerIcons.arrows_sort, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 4),
                        Text(sortLabel, style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
            PageWidth(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: _loading
                    ? const SizedBox(height: 300, child: LoadingPlaceholder())
                    : _items.isEmpty
                        ? EmptyState(
                            icon: TablerIcons.shopping_bag,
                            title: 'Nothing here yet',
                            message: _search.text.isNotEmpty || _category != null
                                ? 'Try another search or category.'
                                : 'Beauty pros will list their products here.',
                          )
                        : ProductGrid(items: _items, onTap: _open),
              ),
            ),
            if (!_loading && _items.isNotEmpty)
              PageWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Text(
                    'You pay the seller directly. BeauTap never holds your money.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// =====================================================================
// Product page
// =====================================================================

class ProductScreen extends StatefulWidget {
  final String productId;
  const ProductScreen({super.key, required this.productId});

  @override
  State<ProductScreen> createState() => _ProductScreenState();
}

class _ProductScreenState extends State<ProductScreen> {
  Map<String, dynamic>? _p;
  List<Map<String, dynamic>> _more = [];
  bool _loading = true;
  int _qty = 1;
  int _photo = 0;
  final _pager = PageController();

  @override
  void initState() {
    super.initState();
    Cart.instance.load();
    _load();
  }

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await supabase.rpc('shop_item', params: {'p_id': widget.productId});
      if (res != null) {
        _p = Map<String, dynamic>.from(res as Map);
        final more = await supabase.rpc('shop_items', params: {'p_seller': _p!['seller_id'], 'p_limit': 9});
        _more = List<Map<String, dynamic>>.from(more as List).where((m) => m['id'] != widget.productId).take(8).toList();
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  bool get _mine => _p?['seller_id'] == myId;
  bool get _out => _p?['in_stock'] == false || (_p?['stock_qty'] is num && (_p!['stock_qty'] as num) <= 0);
  bool get _closed => (_p?['settings'] as Map?)?['accepts_orders'] == false;
  int get _max => (_p?['stock_qty'] as num?)?.toInt().clamp(1, 50) ?? 50;

  void _add({bool buyNow = false}) {
    Haptics.firm();
    Cart.instance.add(CartLine.fromItem(_p!, qty: _qty));
    if (buyNow) {
      context.push('/cart');
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('Added to your cart'),
      action: SnackBarAction(label: 'View cart', onPressed: () => context.push('/cart')),
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(appBar: AppBar(), body: const LoadingPlaceholder(kind: PlaceholderKind.detail));
    }
    final p = _p;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(
          icon: TablerIcons.shopping_bag_x,
          title: 'This item isn\'t for sale',
          message: 'The seller may have sold it or taken it down.',
        ),
      );
    }
    final imgs = ((p['images'] as List?) ?? const []).map((e) => e.toString()).toList();
    final wide = MediaQuery.sizeOf(context).width >= 760;
    final gallery = _Gallery(
      images: imgs,
      controller: _pager,
      index: _photo,
      onPage: (i) => setState(() => _photo = i),
    );
    final info = _info(p);
    return Scaffold(
      appBar: AppBar(actions: [CartButton(onTap: () => context.push('/cart')), const SizedBox(width: 4)]),
      bottomNavigationBar: _bottomBar(p),
      body: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
        if (wide)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ClipRRect(borderRadius: AppRadius.lgAll, child: gallery)),
              const SizedBox(width: 24),
              Expanded(child: info),
            ]),
          )
        else ...[
          gallery,
          Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0), child: info),
        ],
        if (_more.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              sectionLabel('More from ${(p['seller_name'] ?? '').toString().split(' ').first}',
                  trailing: TextButton(
                      onPressed: () => context.push('/shop/seller/${p['seller_id']}'), child: const Text('See all'))),
              ProductGrid(
                  items: _more, showSeller: false, onTap: (m) => context.pushReplacement('/shop/item/${m['id']}')),
            ]),
          ),
      ]),
    );
  }

  Widget _info(Map<String, dynamic> p) {
    final settings = Map<String, dynamic>.from((p['settings'] as Map?) ?? const {});
    final stock = p['stock_qty'] as num?;
    final ways = <(IconData, String)>[
      if (settings['can_collect'] != false)
        (TablerIcons.building_store, 'Collect${(p['area'] ?? '').toString().isNotEmpty ? ' in ${p['area']}' : ''}'),
      if (settings['can_deliver'] == true)
        (TablerIcons.truck_delivery,
            'Delivery${settings['delivery_fee'] != null ? ' · ${money(settings['delivery_fee'] as num)}' : ''}'),
      if (settings['can_post'] == true) (TablerIcons.package, 'Courier / post'),
      if (settings['at_appointment'] != false) (TablerIcons.calendar_event, 'At your appointment'),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        statusChip(p['category'] ?? 'Other', AppColors.goldText),
        const SizedBox(width: 8),
        if ((p['sold'] as num? ?? 0) > 0)
          Text('${p['sold']} sold', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
      ]),
      const SizedBox(height: 10),
      Text(p['name'] ?? '', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text(money(p['price'] as num?),
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: AppColors.textPrimary, height: 1)),
        const SizedBox(width: 10),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            _out ? 'Sold out' : (stock != null && stock <= 5 ? 'Only $stock left' : 'In stock'),
            style: TextStyle(
                fontWeight: FontWeight.w600,
                color: _out ? AppColors.errorText : (stock != null && stock <= 5 ? AppColors.warningText : AppColors.success)),
          ),
        ),
      ]),
      const SizedBox(height: 4),
      Text('Price is a starting point: you can offer a different price when you order.',
          style: TextStyle(fontSize: 12.5, color: AppColors.textTertiary)),
      if ((p['description'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(p['description'], style: TextStyle(fontSize: 15, height: 1.5, color: AppColors.textPrimary)),
      ],
      sectionLabel('How you get it'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final w in ways)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.pill),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(w.$1, size: 16, color: AppColors.textSecondary),
              const SizedBox(width: 6),
              Text(w.$2, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            ]),
          ),
      ]),
      if ((settings['note'] ?? '').toString().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text('“${settings['note']}”', style: TextStyle(fontSize: 13, color: AppColors.textSecondary, fontStyle: FontStyle.italic)),
      ],
      const SizedBox(height: 10),
      Text('You agree on the price, payment and handover with the seller in the order chat, then pay them directly.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.4)),
      sectionLabel('Seller'),
      _SellerCard(
        id: p['seller_id'],
        name: p['seller_name'] ?? '',
        avatar: p['seller_avatar'],
        verified: p['seller_verified'] == true,
        place: [p['area'], p['city']].where((x) => (x ?? '').toString().isNotEmpty).join(', '),
        rating: p['seller_rating'] as num?,
        ratings: (p['seller_ratings'] as num?)?.toInt() ?? 0,
        sold: (p['seller_sold'] as num?)?.toInt() ?? 0,
      ),
    ]);
  }

  Widget _bottomBar(Map<String, dynamic> p) {
    Widget child;
    if (_mine) {
      child = Row(children: [
        Expanded(
          child: Text(p['is_active'] == false ? 'Your item · hidden from the shop' : 'This is your item',
              style: TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
        ),
        FilledButton.icon(
          onPressed: () async {
            await context.push('/provider/shop/item/${p['id']}');
            _load();
          },
          icon: const Icon(TablerIcons.pencil, size: 18),
          label: const Text('Edit'),
        ),
      ]);
    } else if (_out || _closed) {
      child = SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: null,
          child: Text(_out ? 'Sold out' : 'This shop isn\'t taking orders right now'),
        ),
      );
    } else {
      child = Row(children: [
        _QtyStepper(
          value: _qty,
          max: _max,
          onChanged: (v) => setState(() => _qty = v),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(0, 50), padding: EdgeInsets.zero),
            onPressed: _add,
            child: const Text('Add to cart'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 50), padding: EdgeInsets.zero),
            onPressed: () => _add(buyNow: true),
            child: const Text('Buy now'),
          ),
        ),
      ]);
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: BoxDecoration(color: AppColors.card, border: Border(top: BorderSide(color: AppColors.border))),
        child: child,
      ),
    );
  }
}

class _Gallery extends StatelessWidget {
  final List<String> images;
  final PageController controller;
  final int index;
  final ValueChanged<int> onPage;
  const _Gallery({required this.images, required this.controller, required this.index, required this.onPage});

  @override
  Widget build(BuildContext context) {
    if (images.isEmpty) return const AspectRatio(aspectRatio: 1, child: ProductImage(null));
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(children: [
        PageView(
          controller: controller,
          onPageChanged: onPage,
          children: [for (final u in images) ProductImage(u)],
        ),
        if (images.length > 1)
          Positioned(
            bottom: 12,
            left: 0,
            right: 0,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              for (var i = 0; i < images.length; i++)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  width: i == index ? 18 : 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.gold : Colors.white.withValues(alpha: 0.75),
                    borderRadius: AppRadius.pill,
                  ),
                ),
            ]),
          ),
        if (images.length > 1)
          Positioned(
            top: 12,
            right: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: AppRadius.pill),
              child: Text('${index + 1}/${images.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
      ]),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int value;
  final int max;
  final ValueChanged<int> onChanged;
  final bool compact;
  const _QtyStepper({required this.value, required this.max, required this.onChanged, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final h = compact ? 34.0 : 50.0;
    Widget btn(IconData i, VoidCallback? f) => SizedBox(
          width: h,
          height: h,
          child: IconButton(
            padding: EdgeInsets.zero,
            iconSize: compact ? 16 : 18,
            onPressed: f == null
                ? null
                : () {
                    Haptics.light();
                    f();
                  },
            icon: Icon(i),
          ),
        );
    return Container(
      decoration: BoxDecoration(border: Border.all(color: AppColors.borderStrong), borderRadius: AppRadius.pill),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        btn(TablerIcons.minus, value > 1 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: compact ? 22 : 26,
          child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        btn(TablerIcons.plus, value < max ? () => onChanged(value + 1) : null),
      ]),
    );
  }
}

class _SellerCard extends StatelessWidget {
  final String id;
  final String name;
  final String? avatar;
  final bool verified;
  final String place;
  final num? rating;
  final int ratings;
  final int sold;
  const _SellerCard({
    required this.id,
    required this.name,
    this.avatar,
    required this.verified,
    required this.place,
    this.rating,
    required this.ratings,
    required this.sold,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: () => context.push('/shop/seller/$id'),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            PersonAvatar(name: name, url: avatar, size: 48),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 4),
                    const Icon(TablerIcons.rosette_discount_check_filled, size: 17, color: AppColors.gold),
                  ],
                ]),
                const SizedBox(height: 2),
                Text(
                  [
                    if (rating != null) '★ $rating ($ratings)' else 'New seller',
                    if (sold > 0) '$sold order${sold == 1 ? '' : 's'}',
                    if (place.isNotEmpty) place,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
              ]),
            ),
            Text('Shop', style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
            Icon(TablerIcons.chevron_right, size: 18, color: AppColors.primary),
          ]),
        ),
      ),
    );
  }
}

// =====================================================================
// A seller's storefront
// =====================================================================

class SellerShopScreen extends StatefulWidget {
  final String sellerId;
  const SellerShopScreen({super.key, required this.sellerId});

  @override
  State<SellerShopScreen> createState() => _SellerShopScreenState();
}

class _SellerShopScreenState extends State<SellerShopScreen> {
  Map<String, dynamic>? _s;
  List<Map<String, dynamic>> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<dynamic>([
        supabase.rpc('shop_seller', params: {'p_seller': widget.sellerId}),
        supabase.rpc('shop_items', params: {'p_seller': widget.sellerId, 'p_limit': 100}),
      ]);
      if (res[0] != null) _s = Map<String, dynamic>.from(res[0] as Map);
      _items = List<Map<String, dynamic>>.from(res[1] as List);
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = _s;
    return Scaffold(
      appBar: AppBar(
        title: Text(s == null ? 'Shop' : '${(s['name'] ?? '').toString().split(' ').first}\'s shop'),
        actions: [CartButton(onTap: () => context.push('/cart')), const SizedBox(width: 4)],
      ),
      body: _loading
          ? const LoadingPlaceholder()
          : s == null
              ? const EmptyState(icon: TablerIcons.building_store, title: 'Shop not found', message: 'This shop isn\'t available.')
              : RefreshIndicator.adaptive(
                  onRefresh: _load,
                  child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
                    Row(children: [
                      PersonAvatar(name: s['name'] ?? '', url: s['avatar'], size: 64),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Flexible(
                              child: Text(s['name'] ?? '',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                            ),
                            if (s['verified'] == true) ...[
                              const SizedBox(width: 4),
                              const Icon(TablerIcons.rosette_discount_check_filled, size: 19, color: AppColors.gold),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            [
                              if (s['rating'] != null) '★ ${s['rating']} (${s['ratings']})' else 'New seller',
                              if ((s['sold'] as num? ?? 0) > 0) '${s['sold']} orders',
                              [s['area'], s['city']].where((x) => (x ?? '').toString().isNotEmpty).join(', '),
                            ].where((x) => x.isNotEmpty).join(' · '),
                            style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
                          ),
                        ]),
                      ),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.push('/provider/${widget.sellerId}'),
                          icon: const Icon(TablerIcons.calendar_event, size: 18),
                          label: const Text('Book with them'),
                        ),
                      ),
                    ]),
                    if (((s['settings'] as Map?)?['note'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SoftBanner(icon: TablerIcons.info_circle, color: AppColors.primary, title: (s['settings'] as Map)['note']),
                    ],
                    sectionLabel('${_items.length} item${_items.length == 1 ? '' : 's'}'),
                    if (_items.isEmpty)
                      const EmptyState(icon: TablerIcons.shopping_bag, title: 'No items right now', message: 'Check back soon.')
                    else
                      ProductGrid(items: _items, showSeller: false, onTap: (p) => context.push('/shop/item/${p['id']}')),
                    if ((s['reviews'] as List? ?? const []).isNotEmpty) ...[
                      sectionLabel('What buyers say'),
                      for (final r in (s['reviews'] as List))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('★' * ((r['rating'] as num?)?.toInt() ?? 0),
                                style: const TextStyle(color: Color(0xFFA8822F), fontSize: 13)),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${(r['comment'] ?? '').toString().isEmpty ? '' : '“${r['comment']}” '}— ${r['buyer']}',
                                style: TextStyle(fontSize: 13.5, color: AppColors.textPrimary),
                              ),
                            ),
                          ]),
                        ),
                    ],
                  ]),
                ),
    );
  }
}

// =====================================================================
// Cart and checkout (one order request per seller)
// =====================================================================

class CartScreen extends StatefulWidget {
  const CartScreen({super.key});

  @override
  State<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends State<CartScreen> {
  @override
  void initState() {
    super.initState();
    Cart.instance.load();
  }

  Future<void> _checkout(String sellerId, List<CartLine> lines) async {
    if (!isSignedIn) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign in to order'),
          content: const Text('Your cart stays here. Sign in or create a free account, then send your order.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign in')),
          ],
        ),
      );
      if (go == true && mounted) context.push('/login');
      return;
    }
    if (sellerId == myId) {
      shopToast(context, 'You can\'t buy your own items', error: true);
      return;
    }
    final orderId = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _CheckoutSheet(sellerId: sellerId, lines: lines),
    );
    if (orderId == null || !mounted) return;
    Cart.instance.clearSeller(sellerId);
    Haptics.firm();
    context.pushReplacement('/orders/$orderId');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cart')),
      body: ListenableBuilder(
        listenable: Cart.instance,
        builder: (context, _) {
          final groups = Cart.instance.bySeller;
          if (groups.isEmpty) {
            return EmptyState(
              icon: TablerIcons.shopping_cart,
              title: 'Your cart is empty',
              message: 'Find hair, skin and nail products from beauty pros.',
              actionLabel: 'Go to the shop',
              onAction: () => context.canPop() ? context.pop() : context.go('/shop'),
            );
          }
          return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            if (groups.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SoftBanner(
                  icon: TablerIcons.info_circle,
                  color: AppColors.primary,
                  title: '${groups.length} sellers, ${groups.length} orders',
                  message: 'Each seller gets their own order request, so you agree with each one separately.',
                ),
              ),
            for (final e in groups.entries) _sellerCard(e.key, e.value),
          ]);
        },
      ),
    );
  }

  Widget _sellerCard(String sellerId, List<CartLine> lines) {
    final total = lines.fold<num>(0, (s, l) => s + l.price * l.qty);
    final first = lines.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        boxShadow: AppColors.isDark ? null : AppShadows.lifted,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => context.push('/shop/seller/$sellerId'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(children: [
              PersonAvatar(name: first.sellerName, url: first.sellerAvatar, size: 30),
              const SizedBox(width: 10),
              Expanded(child: Text(first.sellerName, style: const TextStyle(fontWeight: FontWeight.w700))),
              Icon(TablerIcons.chevron_right, size: 18, color: AppColors.textTertiary),
            ]),
          ),
        ),
        Divider(height: 1, color: AppColors.border),
        for (final l in lines)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
            child: Row(children: [
              InkWell(
                onTap: () => context.push('/shop/item/${l.productId}'),
                child: SizedBox(width: 60, height: 60, child: ProductImage(l.image, radius: AppRadius.smAll)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(l.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(money(l.price * l.qty),
                      style: TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                ]),
              ),
              _QtyStepper(
                compact: true,
                value: l.qty,
                max: l.maxQty?.clamp(1, 50) ?? 50,
                onChanged: (v) => Cart.instance.setQty(l.productId, v),
              ),
              IconButton(
                tooltip: 'Remove',
                onPressed: () async {
                  Haptics.warn();
                  final saved = [l];
                  Cart.instance.remove(l.productId);
                  final r = await ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(
                        content: Text('Removed ${l.name}'),
                        action: SnackBarAction(label: 'Undo', onPressed: () {}),
                      ))
                      .closed;
                  if (r == SnackBarClosedReason.action) Cart.instance.restore(saved);
                },
                icon: Icon(TablerIcons.trash, size: 19, color: AppColors.textTertiary),
              ),
            ]),
          ),
        Divider(height: 1, color: AppColors.border),
        Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Text('Items', style: TextStyle(color: AppColors.textSecondary)),
              const Spacer(),
              Text(money(total), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17)),
            ]),
            const SizedBox(height: 10),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
              onPressed: () => _checkout(sellerId, lines),
              child: Text('Order from ${first.sellerName.split(' ').first}'),
            ),
            const SizedBox(height: 6),
            Text('Nothing is paid yet. You agree on the price, payment and handover first.',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
          ]),
        ),
      ]),
    );
  }
}

class _CheckoutSheet extends StatefulWidget {
  final String sellerId;
  final List<CartLine> lines;
  const _CheckoutSheet({required this.sellerId, required this.lines});

  @override
  State<_CheckoutSheet> createState() => _CheckoutSheetState();
}

class _CheckoutSheetState extends State<_CheckoutSheet> {
  Map<String, dynamic> _settings = const {};
  List<String> _pays = const ['cash'];
  String _get = 'collect';
  String _pay = 'ecocash';
  final _note = TextEditingController();
  final _offer = TextEditingController();
  bool _offering = false;
  bool _sending = false;

  num get _total => widget.lines.fold<num>(0, (s, l) => s + l.price * l.qty);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    _offer.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<dynamic>([
        supabase.from('shop_settings').select().eq('provider_id', widget.sellerId).maybeSingle(),
        supabase
            .from('provider_profiles')
            .select('accepts_cash, ecocash_number, ecocash_merchant, innbucks_number, onemoney_number, bank_details')
            .eq('provider_id', widget.sellerId)
            .maybeSingle(),
      ]);
      final s = res[0] == null ? <String, dynamic>{} : Map<String, dynamic>.from(res[0] as Map);
      final pp = res[1] == null ? <String, dynamic>{} : Map<String, dynamic>.from(res[1] as Map);
      bool has(String k) => (pp[k] ?? '').toString().trim().isNotEmpty;
      final pays = [
        if (has('ecocash_number') || has('ecocash_merchant')) 'ecocash',
        if (has('innbucks_number')) 'innbucks',
        if (has('onemoney_number')) 'onemoney',
        if (has('bank_details')) 'bank',
        if (pp['accepts_cash'] != false) 'cash',
      ];
      if (mounted) {
        setState(() {
          _settings = s;
          _pays = pays.isEmpty ? const ['ecocash', 'cash'] : pays;
          _pay = _pays.first;
          _get = _gets.first;
        });
      }
    } catch (_) {}
  }

  List<String> get _gets => [
        if (_settings['can_collect'] != false) 'collect',
        if (_settings['can_deliver'] == true) 'deliver',
        if (_settings['can_post'] == true) 'post',
        if (_settings['at_appointment'] != false) 'appointment',
      ].let((l) => l.isEmpty ? ['collect'] : l);

  Future<void> _send() async {
    final offer = _offering ? double.tryParse(_offer.text.trim()) : null;
    if (_offering && (offer == null || offer <= 0)) {
      shopToast(context, 'Enter the price you\'d like to pay, or turn off the offer', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      final id = await supabase.rpc('place_order', params: {
        'p_seller': widget.sellerId,
        'p_items': [
          for (final l in widget.lines) {'product_id': l.productId, 'qty': l.qty}
        ],
        'p_get': _get,
        'p_pay': _pay,
        'p_note': _note.text.trim(),
      }) as String;
      if (offer != null && offer != _total) {
        await supabase.rpc('offer_order_price', params: {'p_order': id, 'p_amount': offer, 'p_note': null});
      }
      if (mounted) Navigator.pop(context, id);
    } catch (e) {
      if (mounted) {
        setState(() => _sending = false);
        shopToast(context, errText(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = _settings['delivery_fee'] as num?;
    return SheetScroll(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Send order request', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            '${widget.lines.first.sellerName.split(' ').first} replies with the terms: the total, how to pay and how you get it. '
            'Nothing is paid until you both agree.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.5, height: 1.4),
          ),
          sectionLabel('How you\'d like to get it'),
          ChoiceRow<String>(
            options: _gets,
            value: _get,
            label: (g) => g == 'deliver' && fee != null ? 'Delivery · ${money(fee)}' : getLabel(g),
            icon: getIcon,
            onChanged: (g) => setState(() => _get = g),
          ),
          sectionLabel('How you\'d like to pay'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final p in _pays)
              ChoiceChip(
                showCheckmark: false,
                selected: _pay == p,
                onSelected: (_) {
                  Haptics.light();
                  setState(() => _pay = p);
                },
                avatar: Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: payBrand(p).bg, borderRadius: BorderRadius.circular(5)),
                  child: Text(payBrand(p).mark[0],
                      style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
                label: Text(payMethodLabel(p)),
              ),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
            decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.mdAll),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Offer a different price', style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Asking ${money(_total)}', style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                  ]),
                ),
                Switch.adaptive(value: _offering, onChanged: (v) => setState(() => _offering = v)),
              ]),
              if (_offering)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 4, 8, 8),
                  child: TextField(
                    controller: _offer,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                    decoration: const InputDecoration(labelText: 'Your price for everything', prefixText: '\$ '),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _note,
            maxLength: 300,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Note for the seller (optional)', hintText: 'e.g. Colour 1B, collect Saturday'),
          ),
          const SizedBox(height: 4),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _sending ? null : _send,
            child: Text(_sending ? 'Sending…' : 'Send request · ${money(_offering ? (double.tryParse(_offer.text) ?? _total) : _total)}'),
          ),
        ]),
      ),
    );
  }
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
