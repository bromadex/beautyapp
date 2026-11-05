import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';
import '../theme.dart';
import 'shop_bits.dart';

/// Home: a strip of shop items, the client's city first and featured ones
/// on top. Tapping opens the product page; "See all" opens the Shop tab.
class ProductFeedSection extends StatefulWidget {
  final String city;
  const ProductFeedSection({super.key, required this.city});

  @override
  State<ProductFeedSection> createState() => _ProductFeedSectionState();
}

class _ProductFeedSectionState extends State<ProductFeedSection> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant ProductFeedSection old) {
    super.didUpdateWidget(old);
    if (old.city != widget.city) _load();
  }

  Future<void> _load() async {
    try {
      final res = await supabase.rpc('shop_items', params: {
        'p_city': widget.city == 'All Zimbabwe' ? null : widget.city,
        'p_limit': 12,
      });
      if (mounted) {
        setState(() => _items = List<Map<String, dynamic>>.from(res as List)
            .where((p) => p['in_stock'] != false)
            .toList());
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('From the shop', style: Theme.of(context).textTheme.titleLarge)),
        TextButton(onPressed: () => context.go('/shop'), child: const Text('See all')),
      ]),
      Text('Products from beauty pros. Order here, pay them directly.',
          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      SizedBox(
        height: 252,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) => SizedBox(
            width: 158,
            child: ProductTile(p: _items[i], onTap: () => context.push('/shop/item/${_items[i]['id']}')),
          ),
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
