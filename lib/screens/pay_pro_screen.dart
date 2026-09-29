import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/pay_methods.dart';
import '../widgets/ui.dart';

/// Client sends money straight to the pro, then taps "I've paid" with a
/// transaction ID or screenshot. The pro confirms whether it arrived.
class PayProScreen extends StatefulWidget {
  final String bookingId;
  const PayProScreen({super.key, required this.bookingId});

  @override
  State<PayProScreen> createState() => _PayProScreenState();
}

class _PayProScreenState extends State<PayProScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _booking;
  Map<String, dynamic>? _pp;
  String _proName = 'your pro';
  List<Map<String, dynamic>> _payments = [];

  String? _methodId;
  final _refCtrl = TextEditingController();
  Uint8List? _proof;
  String _proofType = 'image/jpeg';
  bool _sending = false;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final b = await supabase
          .from('bookings')
          .select('id, ref, status, client_id, provider_id, total_price, deposit_amount, deposit_paid, '
              'payment_status, payment_method, deposit_due_at, provider:profiles!bookings_provider_id_fkey(full_name)')
          .eq('id', widget.bookingId)
          .maybeSingle();
      if (b == null || b['client_id'] != supabase.auth.currentUser?.id) {
        setState(() {
          _error = 'Booking not found';
          _loading = false;
        });
        return;
      }
      final results = await Future.wait<dynamic>([
        supabase
            .from('provider_profiles')
            .select('accepts_cash, ecocash_number, ecocash_name, ecocash_merchant, innbucks_number, '
                'onemoney_number, bank_details, pay_note')
            .eq('provider_id', b['provider_id'])
            .maybeSingle(),
        supabase
            .from('pro_payments')
            .select()
            .eq('booking_id', widget.bookingId)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      setState(() {
        _booking = b;
        _pp = results[0] as Map<String, dynamic>?;
        _payments = List<Map<String, dynamic>>.from(results[1] as List);
        _proName = ((b['provider'] as Map?)?['full_name'] ?? '').toString().trim();
        if (_proName.isEmpty) _proName = 'your pro';
        final methods = _methods;
        if (_methodId == null || !methods.any((m) => m.id == _methodId)) {
          final booked = methods.where((m) => m.id == b['payment_method']);
          _methodId = booked.isNotEmpty ? booked.first.id : (methods.isNotEmpty ? methods.first.id : null);
        }
        _loading = false;
      });
      _ticker?.cancel();
      if (_dueAt != null) {
        _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load this payment. Check your connection.';
          _loading = false;
        });
      }
    }
  }

  // ---------------- derived ----------------

  List<PayMethod> get _methods => payMethodsOf(_pp, includeCash: false);
  PayMethod? get _method {
    final m = _methods.where((m) => m.id == _methodId);
    return m.isEmpty ? null : m.first;
  }

  DateTime? get _dueAt => DateTime.tryParse((_booking?['deposit_due_at'] ?? '').toString())?.toLocal();

  String _countdown(Duration d) {
    if (d.isNegative) return '0:00:00';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${d.inHours}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
  }

  String get _firstName => _proName == 'your pro' ? 'Your pro' : _proName.split(' ').first;

  /// Mirrors public._amount_due on the server.
  (String kind, double amount)? get _due {
    final b = _booking!;
    double n(String k) => ((b[k] as num?) ?? 0).toDouble();
    if (!['pending', 'confirmed', 'completed'].contains(b['status']) || b['payment_status'] == 'paid') return null;
    final total = n('total_price'), deposit = n('deposit_amount');
    final depositPaid = b['deposit_paid'] == true;
    (String, double) r;
    if (deposit > 0 && !depositPaid) {
      r = b['status'] == 'completed' ? ('full', total) : ('deposit', deposit);
    } else if (depositPaid) {
      r = ('balance', (total - deposit).clamp(0, double.infinity).toDouble());
    } else {
      r = ('full', total);
    }
    return r.$2 > 0 ? r : null;
  }

  Map<String, dynamic>? get _open => _payments.where((p) => p['status'] == 'claimed').firstOrNull;
  Map<String, dynamic>? get _lastRejected {
    final last = _payments.firstOrNull;
    return last != null && last['status'] == 'rejected' ? last : null;
  }

  String _money(num v, {bool cents = false}) => '\$${cents ? v.toStringAsFixed(2) : amountText(v)}';

  // ---------------- actions ----------------

  void _toast(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null),
    );
  }

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('$what copied');
  }

  Future<void> _dial(String code) async {
    final ok = await launchUrl(Uri.parse('tel:${Uri.encodeComponent(code)}'));
    if (!ok && mounted) {
      await Clipboard.setData(ClipboardData(text: code));
      if (mounted) _toast('Couldn\'t open the dialler. $code is copied, dial it on your phone.');
    }
  }

  Future<void> _pickProof() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery, imageQuality: 75, maxWidth: 1600);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      _toast('That picture is too big. Try a smaller screenshot.', error: true);
      return;
    }
    final type = picked.mimeType ?? 'image/jpeg';
    setState(() {
      _proof = bytes;
      _proofType = const ['image/png', 'image/webp'].contains(type) ? type : 'image/jpeg';
    });
  }

  Future<void> _submit() async {
    final m = _method;
    if (m == null) return;
    if (_refCtrl.text.trim().isEmpty && _proof == null) {
      _toast('Add the transaction ID from your SMS, or a screenshot', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      String? path;
      if (_proof != null) {
        final uid = supabase.auth.currentUser!.id;
        final ext = _proofType.split('/').last.replaceAll('jpeg', 'jpg');
        path = '$uid/${widget.bookingId}_${DateTime.now().millisecondsSinceEpoch}.$ext';
        await supabase.storage
            .from('payment-proofs')
            .uploadBinary(path, _proof!, fileOptions: FileOptions(contentType: _proofType));
      }
      await supabase.rpc('claim_pro_payment', params: {
        'p_booking': widget.bookingId,
        'p_method': m.id,
        'p_reference': _refCtrl.text.trim().isEmpty ? null : _refCtrl.text.trim(),
        'p_proof_path': path,
      });
      _refCtrl.clear();
      _proof = null;
      await _load();
      if (mounted) _toast('Sent. $_firstName will confirm when they see it.');
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (e) {
      if (mounted) _toast('Could not send. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  // ---------------- UI ----------------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: LoadingPlaceholder(kind: PlaceholderKind.detail));
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(),
        body: EmptyState(
          icon: TablerIcons.receipt_off,
          title: 'Can\'t pay right now',
          message: _error!,
          actionLabel: 'Try again',
          onAction: () {
            setState(() {
              _loading = true;
              _error = null;
            });
            _load();
          },
        ),
      );
    }

    final due = _due;
    final open = _open;
    final canPay = due != null && open == null && _methods.isNotEmpty;
    final title = due == null
        ? 'Payment'
        : due.$1 == 'deposit'
            ? 'Pay the deposit'
            : 'Pay $_firstName';

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(TablerIcons.x),
          onPressed: () => context.canPop() ? context.pop() : context.go('/booking/${widget.bookingId}'),
        ),
        title: Text(title),
        actions: [
          if (_booking!['ref'] != null)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(child: Text('#${_booking!['ref']}', style: monoStyle)),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            if (open != null)
              _waitingCard(open)
            else if (due == null)
              _paidCard()
            else if (_methods.isEmpty)
              _cashOnlyCard(due.$2)
            else ...[
              if (_lastRejected != null) ...[
                SoftBanner(
                  icon: TablerIcons.alert_triangle,
                  color: AppColors.warning,
                  title: '$_firstName hasn\'t received your last payment',
                  message: 'Check the number and transaction ID, then send your proof again. '
                      'If you\'re sure you paid, message them.',
                ),
                const SizedBox(height: 12),
              ],
              _amountCard(due),
              const SizedBox(height: 12),
              _sendYourselfCard(due.$2),
              if (_methods.length > 1) ...[
                const SizedBox(height: 16),
                _otherMethods(),
              ],
              const SizedBox(height: 20),
              _proofSection(),
            ],
          ],
        ),
      ),
      bottomNavigationBar: canPay
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  border: Border(top: BorderSide(color: AppColors.border)),
                ),
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: _sending
                      ? SizedBox(
                          height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.onPrimary))
                      : const Text('I\'ve paid'),
                ),
              ),
            )
          : null,
    );
  }

  Widget _amountCard((String, double) due) {
    final m = _method;
    final ussd = m?.ussd(due.$2);
    final label = switch (due.$1) {
      'deposit' => 'Deposit to $_proName',
      'balance' => 'Balance to $_proName',
      _ => 'Pay $_proName',
    };
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: AppColors.forest, borderRadius: AppRadius.xlAll),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label, style: const TextStyle(color: AppColors.goldLight, fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(_money(due.$2, cents: true),
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
            ]),
          ),
          if (due.$1 == 'deposit' && _dueAt != null)
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              const Text('RELEASED IN',
                  style: TextStyle(
                      color: AppColors.goldLight, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.6)),
              const SizedBox(height: 4),
              Text(_countdown(_dueAt!.difference(DateTime.now())),
                  style: monoStyle.copyWith(color: Colors.white, fontSize: 18)),
            ]),
        ]),
        if (due.$1 == 'deposit') ...[
          const SizedBox(height: 4),
          Text(
              _dueAt != null && _dueAt!.isBefore(DateTime.now())
                  ? 'Time is up. Send it now and tap "I\'ve paid", or the slot may be released.'
                  : _dueAt != null
                      ? 'Send it before the timer ends or the slot is released. The rest is paid on the day.'
                      : 'Secures your booking. The rest is paid on the day.',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.75), fontSize: 13)),
        ],
        if (ussd != null) ...[
          const SizedBox(height: 16),
          SizedBox(
            height: 52,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.gold,
                foregroundColor: AppColors.primaryDark,
                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
              onPressed: () => _dial(ussd),
              icon: const Icon(TablerIcons.device_mobile, size: 20),
              label: const Text('Pay with EcoCash'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Opens your dialler with $ussd. Enter your PIN to send.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ],
      ]),
    );
  }

  Widget _sendYourselfCard(double amount) {
    final m = _method!;
    final amt = _money(amount);
    final strong = TextStyle(fontWeight: FontWeight.w800, color: AppColors.textPrimary);
    final Widget sentence;
    if (m.id == 'bank') {
      sentence = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(TextSpan(children: [
          const TextSpan(text: 'Send '),
          TextSpan(text: amt, style: strong),
          const TextSpan(text: ' by bank transfer to:'),
        ])),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.smAll),
          child: SelectableText(m.account ?? '', style: const TextStyle(fontSize: 14, height: 1.4)),
        ),
      ]);
    } else {
      sentence = Text.rich(TextSpan(children: [
        TextSpan(text: m.isMerchant ? 'Pay ' : 'Send '),
        TextSpan(text: amt, style: strong),
        TextSpan(text: m.isMerchant ? ' to ' : ' to '),
        TextSpan(text: m.displayAccount, style: strong),
        if (m.accountName != null) TextSpan(text: ' (${m.accountName})'),
        TextSpan(text: m.id == 'ecocash' ? '' : ' on ${m.label}'),
      ]));
    }
    final note = (_pp?['pay_note'] ?? '').toString().trim();
    final hint = [
      if (_booking!['ref'] != null && m.id == 'bank') 'Use ${_booking!['ref']} as the payment reference.',
      if (note.isNotEmpty) note,
    ].join(' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(m.ussd(amount) != null ? 'OR SEND IT YOURSELF' : 'HOW TO PAY',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 0.6, color: AppColors.textSecondary)),
        const SizedBox(height: 10),
        DefaultTextStyle.merge(style: const TextStyle(fontSize: 17, height: 1.35), child: sentence),
        const SizedBox(height: 14),
        OutlinedButtonTheme(
          data: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 44),
              textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
            ),
          ),
          child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _copy(m.account ?? '', m.id == 'bank' ? 'Bank details' : (m.isMerchant ? 'Code' : 'Number')),
              icon: const Icon(TablerIcons.copy, size: 18),
              label: Text(m.id == 'bank' ? 'Copy details' : (m.isMerchant ? 'Copy code' : 'Copy number')),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _copy(amountText(amount), 'Amount'),
              icon: const Icon(TablerIcons.copy, size: 18),
              label: const Text('Copy amount'),
            ),
          ),
        ]),
        ),
        if (hint.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            hint,
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        ],
      ]),
    );
  }

  Widget _otherMethods() {
    final others = _methods.where((m) => m.id != _methodId).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('$_firstName also accepts', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in others)
          ActionChip(
            avatar: Icon(m.icon, size: 16, color: AppColors.primary),
            label: Text(m.label),
            backgroundColor: AppColors.primarySoft,
            side: BorderSide.none,
            labelStyle: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700),
            onPressed: () => setState(() => _methodId = m.id),
          ),
        if (_pp?['accepts_cash'] != false)
          Chip(
            avatar: Icon(TablerIcons.cash, size: 16, color: AppColors.textSecondary),
            label: const Text('Cash on the day'),
            side: BorderSide.none,
            backgroundColor: AppColors.surfaceMuted,
          ),
      ]),
    ]);
  }

  Widget _proofSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Already paid? Add proof', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 10),
      TextField(
        controller: _refCtrl,
        textCapitalization: TextCapitalization.characters,
        maxLength: 60,
        decoration: const InputDecoration(
          labelText: 'Transaction ID',
          hintText: 'From your SMS, e.g. MP260929.1402.A1',
          prefixIcon: Icon(TablerIcons.receipt),
          counterText: '',
        ),
      ),
      const SizedBox(height: 10),
      if (_proof != null)
        Stack(children: [
          ClipRRect(
            borderRadius: AppRadius.mdAll,
            child: Image.memory(_proof!, height: 160, width: double.infinity, fit: BoxFit.cover),
          ),
          Positioned(
            top: 6,
            right: 6,
            child: IconButton.filledTonal(
              onPressed: () => setState(() => _proof = null),
              icon: const Icon(TablerIcons.x, size: 18),
              tooltip: 'Remove screenshot',
            ),
          ),
        ])
      else
        InkWell(
          onTap: _pickProof,
          borderRadius: AppRadius.mdAll,
          child: CustomPaint(
            painter: _DashedBorder(),
            child: SizedBox(
              height: 52,
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(TablerIcons.photo_up, size: 20, color: AppColors.textPrimary),
                SizedBox(width: 8),
                Text('Or add a screenshot', style: TextStyle(fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ),
    ]);
  }

  Widget _statusCard({required IconData icon, required Color color, required Color bg, required String title, required String body, List<Widget> actions = const []}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.xlAll),
      child: Column(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(color: AppColors.card, shape: BoxShape.circle),
          child: Icon(icon, color: color, size: 28),
        ),
        const SizedBox(height: 12),
        Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 6),
        Text(body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary, height: 1.4)),
        if (actions.isNotEmpty) ...[const SizedBox(height: 16), ...actions],
      ]),
    );
  }

  Widget _waitingCard(Map<String, dynamic> p) {
    final ref = p['reference'] != null ? ' Ref ${p['reference']}.' : '';
    return _statusCard(
      icon: TablerIcons.clock_hour_4,
      color: AppColors.warningText,
      bg: AppColors.warningSoft,
      title: 'Waiting for $_firstName to confirm',
      body: 'You sent ${_money((p['amount'] as num))} by ${payMethodLabel(p['method'])}.$ref '
          'We\'ll let you know as soon as they confirm it arrived.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.push('/chat/${widget.bookingId}'),
          icon: const Icon(TablerIcons.message_circle, size: 18),
          label: Text('Message $_firstName'),
        ),
      ],
    );
  }

  Widget _paidCard() {
    final b = _booking!;
    final cancelled = b['status'] == 'cancelled' || b['status'] == 'no_show';
    final last = _payments.where((p) => p['status'] == 'confirmed').firstOrNull;
    return _statusCard(
      icon: cancelled ? TablerIcons.calendar_x : TablerIcons.circle_check,
      color: cancelled ? AppColors.textSecondary : AppColors.success,
      bg: cancelled ? AppColors.surfaceMuted : AppColors.successSoft,
      title: cancelled ? 'Nothing to pay' : 'All paid',
      body: cancelled
          ? 'This booking was cancelled.'
          : last != null
              ? '$_firstName confirmed your ${_money(last['amount'] as num)} payment. Thank you!'
              : 'There is nothing to pay on this booking right now.',
      actions: [
        FilledButton(
          onPressed: () => context.canPop() ? context.pop() : context.go('/booking/${widget.bookingId}'),
          child: const Text('Back to booking'),
        ),
      ],
    );
  }

  Widget _cashOnlyCard(double amount) {
    return _statusCard(
      icon: TablerIcons.cash,
      color: AppColors.primary,
      bg: AppColors.primarySoft,
      title: 'Pay in cash on the day',
      body: '$_firstName takes cash only. Bring ${_money(amount)} to your appointment.',
    );
  }
}

class _DashedBorder extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.borderStrong
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(AppRadius.md)));
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + 6), paint);
        d += 10;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
