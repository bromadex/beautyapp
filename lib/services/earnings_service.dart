import '../supabase_client.dart';

/// Money a pro has actually received. Built from two things the pro
/// confirmed themselves:
///  * transfers they marked "Received" (pro_payments), and
///  * bookings they marked as paid, for whatever the transfers didn't cover
///    (usually cash on the day).
/// BeauTap never holds this money; these are the pro's own records.
class EarningEntry {
  final String bookingId;
  final DateTime when;
  final double amount;
  final String method; // ecocash | innbucks | onemoney | bank | cash
  final String kind; // deposit | balance | full | paid
  final String client;
  final String service;

  const EarningEntry({
    required this.bookingId,
    required this.when,
    required this.amount,
    required this.method,
    required this.kind,
    required this.client,
    required this.service,
  });
}

class OwedBooking {
  final String bookingId;
  final DateTime when;
  final double amount;
  final String client;
  final String service;
  const OwedBooking(this.bookingId, this.when, this.amount, this.client, this.service);
}

class Earnings {
  final List<EarningEntry> entries; // newest first
  final List<OwedBooking> owed; // completed but not fully paid
  final List<String> toCheck; // bookings with an "I've paid" claim waiting for the pro

  const Earnings(this.entries, this.owed, this.toCheck);

  double between(DateTime from, DateTime to) => entries
      .where((e) => !e.when.isBefore(from) && e.when.isBefore(to))
      .fold(0.0, (s, e) => s + e.amount);

  double get owedTotal => owed.fold(0.0, (s, o) => s + o.amount);
}

class EarningsService {
  static String _name(Map b, String key) {
    final p = b[key];
    final n = (p is Map ? p['full_name'] : null) ?? b['walkin_name'];
    final s = (n ?? '').toString().trim();
    return s.isEmpty ? 'Client' : s;
  }

  static String _service(Map b) => ((b['services'] as Map?)?['service_name'] ?? 'Appointment').toString();

  static double _n(Object? v) => ((v as num?) ?? 0).toDouble();

  static Future<Earnings> load() async {
    final uid = supabase.auth.currentUser!.id;
    const bookingCols = 'id, booking_time, total_price, payment_method, payment_status, status, walkin_name, '
        'services(service_name), client:profiles!bookings_client_id_fkey(full_name)';

    final payQ = supabase
        .from('pro_payments')
        .select('booking_id, amount, method, kind, status, decided_at, created_at, bookings($bookingCols)')
        .eq('provider_id', uid)
        .inFilter('status', ['confirmed', 'claimed']);
    final paidQ = supabase
        .from('bookings')
        .select(bookingCols)
        .eq('provider_id', uid)
        .eq('payment_status', 'paid');
    final owedQ = supabase
        .from('bookings')
        .select(bookingCols)
        .eq('provider_id', uid)
        .eq('status', 'completed')
        .neq('payment_status', 'paid')
        .order('booking_time', ascending: false)
        .limit(50);

    final res = await Future.wait<dynamic>([payQ, paidQ, owedQ]);
    final pays = List<Map<String, dynamic>>.from(res[0] as List);
    final paid = List<Map<String, dynamic>>.from(res[1] as List);
    final owedRows = List<Map<String, dynamic>>.from(res[2] as List);

    final entries = <EarningEntry>[];
    final transferred = <String, double>{};
    final toCheck = <String>[];

    for (final p in pays) {
      if (p['status'] == 'claimed') {
        toCheck.add(p['booking_id']);
        continue;
      }
      final b = (p['bookings'] as Map?) ?? const {};
      final amount = _n(p['amount']);
      transferred[p['booking_id']] = (transferred[p['booking_id']] ?? 0) + amount;
      entries.add(EarningEntry(
        bookingId: p['booking_id'],
        when: DateTime.parse(p['decided_at'] ?? p['created_at']).toLocal(),
        amount: amount,
        method: p['method'] ?? 'ecocash',
        kind: p['kind'] ?? 'full',
        client: _name(b, 'client'),
        service: _service(b),
      ));
    }

    // Whatever the confirmed transfers didn't cover was paid another way.
    for (final b in paid) {
      final rest = _n(b['total_price']) - (transferred[b['id']] ?? 0);
      if (rest <= 0.004) continue;
      final m = (b['payment_method'] ?? 'cash').toString();
      entries.add(EarningEntry(
        bookingId: b['id'],
        when: DateTime.parse(b['booking_time']).toLocal(),
        amount: double.parse(rest.toStringAsFixed(2)),
        method: m == 'paynow' ? 'cash' : m,
        kind: 'paid',
        client: _name(b, 'client'),
        service: _service(b),
      ));
    }
    entries.sort((a, b) => b.when.compareTo(a.when));

    final owed = <OwedBooking>[];
    for (final b in owedRows) {
      // Deposits confirmed on these bookings already count as earned.
      final got = pays
          .where((p) => p['booking_id'] == b['id'] && p['status'] == 'confirmed')
          .fold(0.0, (s, p) => s + _n(p['amount']));
      final left = _n(b['total_price']) - got;
      if (left <= 0.004) continue;
      owed.add(OwedBooking(b['id'], DateTime.parse(b['booking_time']).toLocal(), left, _name(b, 'client'), _service(b)));
    }

    return Earnings(entries, owed, toCheck);
  }
}
