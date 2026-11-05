import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../services/cart.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../utils/pay_methods.dart' show amountText;
import 'ui.dart';

const shopCategories = ['Hair', 'Wigs & extensions', 'Skin care', 'Nails', 'Makeup', 'Tools', 'Other'];

IconData shopCategoryIcon(String c) => switch (c) {
      'Hair' => TablerIcons.droplet,
      'Wigs & extensions' => TablerIcons.wand,
      'Skin care' => TablerIcons.sparkles,
      'Nails' => TablerIcons.brush,
      'Makeup' => TablerIcons.palette,
      'Tools' => TablerIcons.scissors,
      _ => TablerIcons.shopping_bag,
    };

const getOptions = ['collect', 'deliver', 'post', 'appointment'];
const payOptions = ['ecocash', 'innbucks', 'onemoney', 'bank', 'cash'];

String getLabel(String? g) => switch (g) {
      'deliver' => 'Delivery',
      'post' => 'Courier / post',
      'appointment' => 'At my appointment',
      _ => 'Collect',
    };

IconData getIcon(String? g) => switch (g) {
      'deliver' => TablerIcons.truck_delivery,
      'post' => TablerIcons.package,
      'appointment' => TablerIcons.calendar_event,
      _ => TablerIcons.building_store,
    };

String money(num? v) => v == null ? '—' : '\$${amountText(v)}';

bool get isSignedIn {
  final u = supabase.auth.currentUser;
  return u != null && u.isAnonymous != true;
}

String? get myId => supabase.auth.currentUser?.id;

/// What a status means for the person looking at it.
({String label, Color color, bool mine}) orderStatus(Map<String, dynamic> o, {required bool asSeller}) {
  final s = o['status'] as String? ?? 'requested';
  final paidSent = o['buyer_paid_at'] != null;
  final get = (o['terms'] as Map?)?['get'] ?? o['pref_get'];
  final away = get == 'deliver' || get == 'post';
  final gold = AppColors.goldText;
  final green = AppColors.success;
  final grey = AppColors.textSecondary;
  return switch (s) {
    'requested' when asSeller => (label: o['buyer_offer'] != null ? 'Price offer' : 'New: send terms', color: gold, mine: true),
    'requested' => (label: 'Waiting for terms', color: grey, mine: false),
    'terms_sent' when asSeller => (label: 'Waiting for buyer', color: grey, mine: false),
    'terms_sent' => (label: 'Terms to check', color: gold, mine: true),
    'agreed' when asSeller => paidSent
        ? (label: 'Check payment', color: gold, mine: true)
        : (label: 'Waiting for payment', color: grey, mine: false),
    'agreed' => paidSent
        ? (label: 'Payment sent', color: grey, mine: false)
        : (label: 'Pay the seller', color: gold, mine: true),
    'paid' when asSeller => (label: away ? 'Paid: send it' : 'Paid: get it ready', color: gold, mine: true),
    'paid' => (label: 'Paid · being prepared', color: green, mine: false),
    'ready' when asSeller => (label: away ? 'On its way' : 'Ready to collect', color: green, mine: false),
    'ready' => (label: away ? 'On its way' : 'Ready to collect', color: gold, mine: true),
    'done' => (label: 'Complete', color: green, mine: false),
    'declined' => (label: 'Declined', color: AppColors.errorText, mine: false),
    _ => (label: 'Cancelled', color: grey, mine: false),
  };
}

Widget statusChip(String label, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: AppRadius.pill),
      child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
    );

/// Square-ish product photo with a fallback.
class ProductImage extends StatelessWidget {
  final String? url;
  final double? height;
  final BorderRadius? radius;
  const ProductImage(this.url, {super.key, this.height, this.radius});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      color: AppColors.primarySoft,
      alignment: Alignment.center,
      child: Icon(TablerIcons.shopping_bag, color: AppColors.primary),
    );
    final img = (url ?? '').isEmpty
        ? fallback
        : Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback);
    return ClipRRect(
      borderRadius: radius ?? BorderRadius.zero,
      child: SizedBox(height: height, width: double.infinity, child: img),
    );
  }
}

/// A product in the shop grid.
class ProductTile extends StatelessWidget {
  final Map<String, dynamic> p;
  final VoidCallback onTap;
  final bool showSeller;
  const ProductTile({super.key, required this.p, required this.onTap, this.showSeller = true});

  @override
  Widget build(BuildContext context) {
    final imgs = (p['images'] as List?) ?? const [];
    final out = p['in_stock'] == false || (p['stock_qty'] is num && (p['stock_qty'] as num) <= 0);
    final mine = p['seller_id'] == myId;
    final low = !out && p['stock_qty'] is num && (p['stock_qty'] as num) <= 3;
    return Material(
      color: AppColors.card,
      borderRadius: AppRadius.mdAll,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          Haptics.light();
          onTap();
        },
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AspectRatio(
            aspectRatio: 1,
            child: Stack(fit: StackFit.expand, children: [
              ProductImage(imgs.isEmpty ? null : imgs.first.toString()),
              if (out)
                Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  alignment: Alignment.center,
                  child: const Text('Sold out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              if (p['boosted'] == true && !out)
                const Positioned(top: 8, left: 8, child: Pill(label: 'Featured', color: AppColors.gold, solid: true)),
              if (mine)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: AppRadius.pill),
                    child: const Text('Yours', style: TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w700)),
                  ),
                ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p['name'] ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, height: 1.25, color: AppColors.textPrimary)),
              const SizedBox(height: 4),
              Row(children: [
                Text(money(p['price'] as num?),
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5, color: AppColors.textPrimary)),
                const Spacer(),
                if (low)
                  Text('${p['stock_qty']} left',
                      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: AppColors.warningText)),
              ]),
              if (showSeller) ...[
                const SizedBox(height: 6),
                Row(children: [
                  PersonAvatar(name: p['seller_name'] ?? '', url: p['seller_avatar'], size: 18),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      [
                        (p['seller_name'] ?? '').toString().split(' ').first,
                        if ((p['city'] ?? '').toString().isNotEmpty) p['city'],
                      ].join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ),
                  if (p['seller_rating'] != null) ...[
                    const Icon(TablerIcons.star_filled, size: 12, color: Color(0xFFA8822F)),
                    const SizedBox(width: 2),
                    Text('${p['seller_rating']}', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ]),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Grid of product tiles: 2 across on phones, more on wide screens.
class ProductGrid extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic>) onTap;
  final bool showSeller;
  const ProductGrid({super.key, required this.items, required this.onTap, this.showSeller = true});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      const gap = 12.0;
      final cols = ((c.maxWidth + gap) / (180 + gap)).floor().clamp(2, 5);
      final w = (c.maxWidth - gap * (cols - 1)) / cols;
      return Wrap(spacing: gap, runSpacing: gap, children: [
        for (final p in items)
          SizedBox(width: w, child: ProductTile(p: p, onTap: () => onTap(p), showSeller: showSeller)),
      ]);
    });
  }
}

/// Cart button with a count, for app bars.
class CartButton extends StatelessWidget {
  final VoidCallback onTap;
  const CartButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Cart.instance,
      builder: (context, _) {
        final n = Cart.instance.count;
        return IconButton(
          tooltip: 'Cart',
          onPressed: onTap,
          icon: Badge(
            isLabelVisible: n > 0,
            label: Text('$n'),
            backgroundColor: AppColors.gold,
            textColor: Colors.black,
            child: const Icon(TablerIcons.shopping_cart),
          ),
        );
      },
    );
  }
}

/// Choice chips in a wrap.
class ChoiceRow<T> extends StatelessWidget {
  final List<T> options;
  final T? value;
  final String Function(T) label;
  final IconData Function(T)? icon;
  final ValueChanged<T> onChanged;
  final bool Function(T)? enabled;
  const ChoiceRow({
    super.key,
    required this.options,
    required this.value,
    required this.label,
    required this.onChanged,
    this.icon,
    this.enabled,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      for (final o in options)
        if (enabled?.call(o) ?? true)
          ChoiceChip(
            label: Text(label(o)),
            avatar: icon == null ? null : Icon(icon!(o), size: 16),
            selected: o == value,
            showCheckmark: false,
            onSelected: (_) {
              Haptics.light();
              onChanged(o);
            },
          ),
    ]);
  }
}

Widget sectionLabel(String t, {Widget? trailing}) => Padding(
      padding: const EdgeInsets.fromLTRB(2, 20, 2, 8),
      child: Row(children: [
        Expanded(
          child: Text(t.toUpperCase(),
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 1, color: AppColors.textSecondary)),
        ),
        ?trailing,
      ]),
    );

void shopToast(BuildContext context, String m, {bool error = false}) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

/// Postgrest/other errors as a short message.
String errText(Object e) => e is PostgrestException ? e.message : 'Something went wrong. Try again.';
