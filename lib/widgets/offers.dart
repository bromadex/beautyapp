import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import 'ui.dart';

/// Offers pros chose to show publicly (Home banner, Browse tiles).
Future<List<Map<String, dynamic>>> loadPublicOffers({int limit = 10}) async {
  try {
    final rows = await supabase.rpc('public_offers', params: {'p_limit': limit}) as List;
    return List<Map<String, dynamic>>.from(rows);
  } catch (_) {
    return const [];
  }
}

/// Codes picked from a public offer, by pro. The booking page fills the
/// code in and applies it, so the client never has to type it.
class OfferMemory {
  static final Map<String, String> _codes = {};
  static void remember(String providerId, String code) => _codes[providerId] = code;
  static String? take(String providerId) => _codes.remove(providerId);
}

String offerTitle(Map<String, dynamic> o) {
  final desc = (o['description'] ?? '').toString().trim();
  if (desc.isNotEmpty) return desc;
  final v = (o['discount_value'] as num?)?.toDouble() ?? 0;
  final amount = o['discount_type'] == 'percentage' ? '${v.toStringAsFixed(0)}% off' : '\$${v.toStringAsFixed(0)} off';
  return '$amount your booking';
}

String offerSubtitle(Map<String, dynamic> o) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final until = DateTime.tryParse((o['valid_until'] ?? '').toString())?.toLocal();
  final min = (o['min_order_amount'] as num?)?.toDouble() ?? 0;
  return [
    if (until != null) 'Until ${until.day} ${months[until.month - 1]}',
    if (min > 0) 'on \$${min.toStringAsFixed(0)}+',
    'code ${o['code']}',
  ].join(' · ');
}

void openOffer(BuildContext context, Map<String, dynamic> o) {
  Haptics.light();
  OfferMemory.remember(o['provider_id'] as String, (o['code'] ?? '').toString());
  context.push('/provider/${o['provider_id']}');
}

/// The black Home banner, like "Post a request", for a public offer.
class OfferBanner extends StatelessWidget {
  final Map<String, dynamic> offer;
  final String? photo;
  const OfferBanner({super.key, required this.offer, this.photo});

  @override
  Widget build(BuildContext context) {
    final o = offer;
    final who = [o['pro_name'], o['area']].where((x) => (x ?? '').toString().isNotEmpty).join(' · ');
    return Semantics(
      button: true,
      label: 'Offer from ${o['pro_name']}: ${offerTitle(o)}',
      child: Material(
        color: AppColors.isDark ? const Color(0xFF1E1912) : const Color(0xFF141210),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => openOffer(context, o),
          child: SizedBox(
            height: 170,
            child: Stack(children: [
              Positioned(
                right: -4,
                bottom: 0,
                width: 150,
                height: 176,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(80)),
                  child: photo != null
                      ? ProPhoto(name: (o['pro_name'] ?? '').toString(), url: photo, radius: 0)
                      : Image.asset('assets/photos/offer_default.jpg', fit: BoxFit.cover, cacheWidth: 450),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 160, 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(who.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: AppColors.gold)),
                  const SizedBox(height: 6),
                  Text(offerTitle(o),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'InterDisplay',
                          fontSize: 21,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: -0.4,
                          color: Color(0xFFF7F3EC))),
                  const SizedBox(height: 4),
                  Text(offerSubtitle(o),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: Color(0xFFCFC6B8))),
                  const Spacer(),
                  Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(color: const Color(0xFFF7F3EC), borderRadius: BorderRadius.circular(20)),
                    child: const Row(mainAxisSize: MainAxisSize.min, children: [
                      Text('Book now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF17130E))),
                      SizedBox(width: 6),
                      Icon(TablerIcons.arrow_right, size: 16, color: Color(0xFF17130E)),
                    ]),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The green offer tile in Browse.
class OfferTile extends StatelessWidget {
  final Map<String, dynamic> offer;
  const OfferTile({super.key, required this.offer});

  @override
  Widget build(BuildContext context) {
    final o = offer;
    return Material(
      color: AppColors.isDark ? const Color(0xFF123D31) : const Color(0xFF0F3B31),
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => openOffer(context, o),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('OFFER · ${(o['pro_name'] ?? '').toString().toUpperCase()}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.8, color: Color(0xFFE7CF9E))),
                const SizedBox(height: 3),
                Text(offerTitle(o),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: Color(0xFFF7F3EC))),
                Text(offerSubtitle(o),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Color(0xFFB9CFC6))),
              ]),
            ),
            const Icon(TablerIcons.chevron_right, color: Color(0xFFE7CF9E)),
          ]),
        ),
      ),
    );
  }
}
