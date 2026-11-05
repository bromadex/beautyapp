import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../utils/pay_methods.dart';

String pkgMoney(num v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

/// A pro's active monthly packages with their items and what the items
/// would cost booked one by one.
Future<List<Map<String, dynamic>>> loadPackagesFor(String providerId) async {
  try {
    final rows = await supabase
        .from('monthly_packages')
        .select('id, name, description, price, is_active, '
            'monthly_package_items(quantity, service_id, tier_id, services(service_name, price), service_tiers(name, price))')
        .eq('provider_id', providerId)
        .eq('is_active', true)
        .order('price');
    return List<Map<String, dynamic>>.from(rows);
  } catch (_) {
    return const [];
  }
}

List<Map<String, dynamic>> packageItems(Map<String, dynamic> p) =>
    List<Map<String, dynamic>>.from(p['monthly_package_items'] as List? ?? const []);

String itemName(Map<String, dynamic> i) {
  final s = (i['services'] as Map?)?['service_name'] ?? 'Service';
  final t = (i['service_tiers'] as Map?)?['name'];
  return t == null ? '$s' : '$s · $t';
}

double itemPrice(Map<String, dynamic> i) =>
    (((i['service_tiers'] as Map?)?['price'] ?? (i['services'] as Map?)?['price']) as num?)?.toDouble() ?? 0;

double packageWorth(Map<String, dynamic> p) =>
    packageItems(p).fold(0.0, (s, i) => s + itemPrice(i) * ((i['quantity'] as num?) ?? 1));

int packageVisits(Map<String, dynamic> p) =>
    packageItems(p).fold(0, (s, i) => s + ((i['quantity'] as num?) ?? 1).toInt());

/// The black package card on a pro's profile.
class PackageCard extends StatelessWidget {
  final Map<String, dynamic> pkg;
  final String proName;
  final VoidCallback? onJoin;
  final bool joined;
  const PackageCard({super.key, required this.pkg, required this.proName, this.onJoin, this.joined = false});

  @override
  Widget build(BuildContext context) {
    final price = (pkg['price'] as num).toDouble();
    final worth = packageWorth(pkg);
    final save = worth - price;
    final dark = AppColors.isDark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? null : const Color(0xFF141210),
        gradient: dark ? const LinearGradient(colors: [Color(0xFF2A2116), Color(0xFF120F0B)]) : null,
        borderRadius: BorderRadius.circular(24),
        border: dark ? Border.all(color: const Color(0xFF2F2A22)) : null,
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${proName.split(' ').first.toUpperCase()} · MONTHLY',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.9, color: AppColors.gold)),
              const SizedBox(height: 4),
              Text(pkg['name'] ?? 'Package',
                  style: const TextStyle(
                      fontFamily: 'InterDisplay', fontSize: 22, fontWeight: FontWeight.w700, color: Color(0xFFF7F3EC))),
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: pkgMoney(price),
                    style: const TextStyle(fontFamily: 'InterDisplay', fontSize: 24, fontWeight: FontWeight.w700, color: Color(0xFFF7F3EC))),
                const TextSpan(text: ' / month', style: TextStyle(fontSize: 13, color: Color(0xFFCFC6B8))),
              ])),
            ]),
          ),
          if (save >= 1)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(12)),
              child: Text('Save ${pkgMoney(save.roundToDouble())}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
            ),
        ]),
        const SizedBox(height: 10),
        for (final i in packageItems(pkg))
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(children: [
              const Icon(TablerIcons.check, size: 16, color: AppColors.gold),
              const SizedBox(width: 8),
              Expanded(
                child: Text('${i['quantity']}× ${itemName(i)}',
                    style: const TextStyle(fontSize: 13.5, color: Color(0xFFE8E0D2))),
              ),
            ]),
          ),
        if ((pkg['description'] ?? '').toString().trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(pkg['description'], style: const TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFFBDB3A4))),
          ),
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Book any free time, like normal · cancel any time',
              style: TextStyle(fontSize: 12, color: Color(0xFFA39A8D))),
        ),
        if (onJoin != null) ...[
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 44,
            child: FilledButton(
              onPressed: joined ? null : onJoin,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF7F3EC),
                foregroundColor: const Color(0xFF17130E),
                disabledBackgroundColor: const Color(0x33F7F3EC),
                disabledForegroundColor: const Color(0xFFE8E0D2),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              child: Text(joined ? 'You\'re a member' : 'Join for ${pkgMoney(price)} a month'),
            ),
          ),
        ],
      ]),
    );
  }
}

/// "Join Braid care": how paying the pro works, then join.
Future<void> showJoinPackageSheet(BuildContext context, Map<String, dynamic> pkg, String proName,
    Map<String, dynamic>? providerProfile) async {
  final first = proName.split(' ').first;
  final price = pkgMoney((pkg['price'] as num).toDouble());
  final methods = payMethodsOf(providerProfile).map((m) => m.label).join(', ');
  const months = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];
  final month = months[DateTime.now().month - 1];
  final visits = packageVisits(pkg);
  Widget step(int n, String title, String body) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
            child: Text('$n', style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
              Text(body, style: TextStyle(fontSize: 13, height: 1.4, color: AppColors.textSecondary)),
            ]),
          ),
        ]),
      );
  final joined = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) {
      var busy = false;
      return StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Join ${pkg['name']}',
                  style: TextStyle(fontFamily: AppTheme.displayFamily, fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              step(1, 'Send $first $price for $month',
                  'By ${methods.isEmpty ? 'cash' : methods}. BeauTap never holds your money.'),
              step(2, '$first confirms it arrived', 'Your $visits ${visits == 1 ? 'visit' : 'visits'} for $month unlock.'),
              step(3, 'Book as usual', 'Package visits show \$0 to pay. Cancel any time before the next month.'),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setSheet(() => busy = true);
                          try {
                            await supabase.rpc('join_package', params: {'p_package': pkg['id']});
                            Haptics.firm();
                            if (ctx.mounted) Navigator.pop(ctx, true);
                          } on PostgrestException catch (e) {
                            setSheet(() => busy = false);
                            if (ctx.mounted) {
                              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
                            }
                          }
                        },
                  style: FilledButton.styleFrom(shape: const StadiumBorder()),
                  child: Text(busy ? 'Joining…' : 'Join and pay $first'),
                ),
              ),
            ]),
          ),
        ),
      );
    },
  );
  if (joined == true && context.mounted) context.push('/packages');
}
