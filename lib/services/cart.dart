import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One line in the cart. Price, name and photo are what the buyer saw;
/// the server re-checks them when the order is sent.
class CartLine {
  final String productId;
  final String sellerId;
  final String sellerName;
  final String? sellerAvatar;
  final String name;
  final String? image;
  final num price;
  int qty;
  final int? maxQty;

  CartLine({
    required this.productId,
    required this.sellerId,
    required this.sellerName,
    this.sellerAvatar,
    required this.name,
    this.image,
    required this.price,
    this.qty = 1,
    this.maxQty,
  });

  Map<String, dynamic> toJson() => {
        'p': productId,
        's': sellerId,
        'sn': sellerName,
        'sa': sellerAvatar,
        'n': name,
        'i': image,
        'pr': price,
        'q': qty,
        'm': maxQty,
      };

  static CartLine fromJson(Map<String, dynamic> j) => CartLine(
        productId: j['p'],
        sellerId: j['s'],
        sellerName: j['sn'] ?? '',
        sellerAvatar: j['sa'],
        name: j['n'] ?? '',
        image: j['i'],
        price: j['pr'] ?? 0,
        qty: (j['q'] as num?)?.toInt() ?? 1,
        maxQty: (j['m'] as num?)?.toInt(),
      );

  /// From a shop_items row.
  static CartLine fromItem(Map<String, dynamic> p, {int qty = 1}) {
    final imgs = (p['images'] as List?) ?? const [];
    return CartLine(
      productId: p['id'],
      sellerId: p['seller_id'],
      sellerName: p['seller_name'] ?? '',
      sellerAvatar: p['seller_avatar'],
      name: p['name'] ?? '',
      image: imgs.isEmpty ? null : imgs.first.toString(),
      price: (p['price'] as num?) ?? 0,
      qty: qty,
      maxQty: (p['stock_qty'] as num?)?.toInt(),
    );
  }
}

/// The shop cart: kept on this device, split by seller at checkout (one
/// order request per seller).
class Cart extends ChangeNotifier {
  Cart._();
  static final Cart instance = Cart._();
  static const _key = 'shop_cart_v1';

  final List<CartLine> _lines = [];
  bool _loaded = false;

  List<CartLine> get lines => List.unmodifiable(_lines);
  int get count => _lines.fold(0, (n, l) => n + l.qty);
  bool contains(String productId) => _lines.any((l) => l.productId == productId);

  /// Lines grouped by seller, in the order they were added.
  Map<String, List<CartLine>> get bySeller {
    final m = <String, List<CartLine>>{};
    for (final l in _lines) {
      m.putIfAbsent(l.sellerId, () => []).add(l);
    }
    return m;
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw != null) {
        _lines
          ..clear()
          ..addAll((jsonDecode(raw) as List).map((e) => CartLine.fromJson(Map<String, dynamic>.from(e))));
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    notifyListeners();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(_lines.map((l) => l.toJson()).toList()));
    } catch (_) {}
  }

  void add(CartLine line) {
    final i = _lines.indexWhere((l) => l.productId == line.productId);
    if (i >= 0) {
      final l = _lines[i];
      l.qty = (l.qty + line.qty).clamp(1, l.maxQty ?? 50);
    } else {
      _lines.add(line);
    }
    _save();
  }

  void setQty(String productId, int qty) {
    final i = _lines.indexWhere((l) => l.productId == productId);
    if (i < 0) return;
    if (qty <= 0) {
      _lines.removeAt(i);
    } else {
      _lines[i].qty = qty.clamp(1, _lines[i].maxQty ?? 50);
    }
    _save();
  }

  void remove(String productId) => setQty(productId, 0);

  void clearSeller(String sellerId) {
    _lines.removeWhere((l) => l.sellerId == sellerId);
    _save();
  }

  /// Puts lines back (undo).
  void restore(List<CartLine> lines) {
    for (final l in lines) {
      if (!contains(l.productId)) _lines.add(l);
    }
    _save();
  }
}
