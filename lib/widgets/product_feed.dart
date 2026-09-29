import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart' show shareOnWhatsApp;
import '../utils/pay_methods.dart' show amountText;
import 'ui.dart';

/// Home: products pros are advertising in the client's city. Boosted ones
/// come first. Advertising only: clients ask the pro on WhatsApp to buy.
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
      final res = await supabase.rpc('products_feed', params: {'p_city': widget.city, 'p_limit': 12});
      if (mounted) setState(() => _items = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {}
  }

  void _open(Map<String, dynamic> p) {
    final contact = (p['contact'] ?? '').toString();
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
              if ((p['image_url'] ?? '').toString().isNotEmpty) ...[
                ClipRRect(borderRadius: AppRadius.mdAll, child: Image.network(p['image_url'], height: 220, fit: BoxFit.cover)),
                const SizedBox(height: 14),
              ],
              Text(p['name'] ?? '', style: Theme.of(ctx).textTheme.headlineSmall),
              if (p['price'] != null)
                Text('\$${amountText(p['price'] as num)}',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.primary)),
              if ((p['description'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(p['description'], style: TextStyle(color: AppColors.textSecondary, height: 1.45)),
              ],
              const SizedBox(height: 14),
              Row(children: [
                PersonAvatar(name: p['pro_name'] ?? '', url: p['avatar_url'], size: 36),
                const SizedBox(width: 10),
                Expanded(
                  child: Text('Sold by ${p['pro_name'] ?? 'a beauty pro'} · ${p['area'] ?? ''}, ${p['city'] ?? ''}',
                      style: TextStyle(color: AppColors.textSecondary)),
                ),
              ]),
              const SizedBox(height: 16),
              if (contact.isNotEmpty)
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white),
                  onPressed: () => shareOnWhatsApp(
                      'Hi ${p['pro_name'] ?? ''}, I saw your ${p['name']} on BeauTap. Is it available?',
                      phone: contact),
                  icon: const Icon(TablerIcons.brand_whatsapp),
                  label: const Text('Ask on WhatsApp'),
                ),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  context.push('/provider/${p['provider_id']}');
                },
                child: const Text('See this pro'),
              ),
              const SizedBox(height: 6),
              Text('BeauTap only shows the ad. You pay the pro directly.',
                  textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('From beauty pros near you', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 2),
      Text('Products they sell. Ask them on WhatsApp.', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
      const SizedBox(height: 10),
      SizedBox(
        height: 206,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _items.length,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final p = _items[i];
            final img = (p['image_url'] ?? '').toString();
            return InkWell(
              onTap: () => _open(p),
              borderRadius: AppRadius.mdAll,
              child: Container(
                width: 148,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(color: p['boosted'] == true ? AppColors.gold : AppColors.border),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Stack(children: [
                    SizedBox(
                      height: 118,
                      width: double.infinity,
                      child: img.isEmpty
                          ? Container(color: AppColors.primarySoft, child: Icon(TablerIcons.shopping_bag, color: AppColors.primary))
                          : Image.network(img, fit: BoxFit.cover),
                    ),
                    if (p['boosted'] == true)
                      const Positioned(top: 6, left: 6, child: Pill(label: 'Featured', color: AppColors.gold, solid: true)),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(p['name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (p['price'] != null)
                        Text('\$${amountText(p['price'] as num)}',
                            style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w800)),
                      Text(p['pro_name'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                ]),
              ),
            );
          },
        ),
      ),
      const SizedBox(height: 24),
    ]);
  }
}
