import 'package:url_launcher/url_launcher.dart';

/// Helpers for bookings that may be walk-ins (no BeauTap account).

bool isManualBooking(Map b) => b['source'] == 'manual';

/// Fills `b[key]` with the walk-in's name and phone when there is no linked profile,
/// so screens can keep reading `b[key]['full_name']`.
void fillWalkin(Map<String, dynamic> b, String key) {
  if (b[key] == null && b['walkin_name'] != null) {
    b[key] = {'full_name': b['walkin_name'], 'phone': b['walkin_phone']};
  }
}

/// Same key the database uses to group a stylist's clients.
String clientKeyOf(Map b) {
  if (b['client_id'] != null) return b['client_id'];
  if (b['walkin_phone'] != null) return 'tel:${b['walkin_phone']}';
  return 'name:${(b['walkin_name'] ?? '').toString().trim().toLowerCase()}';
}

String money(num v) => '\$${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';

/// Plain-text receipt that reads well in WhatsApp.
String receiptText(Map b, {required String stylist, required String client}) {
  const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final t = DateTime.tryParse(b['booking_time'] ?? '')?.toLocal();
  final when = t == null
      ? ''
      : '${t.day} ${months[t.month - 1]} ${t.year}, ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  final service = [
    b['service_tiers']?['name'],
    b['services']?['service_name'],
  ].where((x) => x != null).join(' · ');
  num n(String k) => (b[k] as num?) ?? 0;
  final lines = <String>[
    '*BeauTap receipt*',
    if (b['ref'] != null) 'Ref: #${b['ref']}',
    'Stylist: $stylist',
    'Client: $client',
    if (when.isNotEmpty) 'Date: $when',
    '',
    if (service.isNotEmpty) service,
    for (final a in (b['booking_addons'] as List? ?? [])) '+ ${a['addon_name']}  ${money((a['addon_price'] as num?) ?? 0)}',
    if (n('travel_fee') > 0) 'Travel: ${money(n('travel_fee'))}',
    if (n('discount_amount') > 0) 'Promo: -${money(n('discount_amount'))}',
    if (n('loyalty_discount') > 0) 'Loyalty reward: -${money(n('loyalty_discount'))}',
    '*Total: ${money(n('total_price'))}*',
    if (b['deposit_paid'] == true && n('deposit_amount') > 0) 'Deposit paid: ${money(n('deposit_amount'))}',
    b['payment_status'] == 'paid' ? 'Status: PAID' : 'Status: not yet paid',
    '',
    'Thank you! Book again on BeauTap.',
  ];
  return lines.join('\n');
}

/// Opens WhatsApp with [text]; goes straight to [phone] when known.
Future<void> shareOnWhatsApp(String text, {String? phone}) async {
  final digits = (phone ?? '').replaceAll(RegExp(r'\D'), '');
  final to = digits.isEmpty
      ? ''
      : digits.startsWith('263')
          ? digits
          : digits.startsWith('0')
              ? '263${digits.substring(1)}'
              : digits;
  await launchUrl(Uri.parse('https://wa.me/$to?text=${Uri.encodeComponent(text)}'),
      mode: LaunchMode.externalApplication);
}
