import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';

import '../services/fee_checkout.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/pay_methods.dart';
import '../widgets/ui.dart';

/// Backup for when Paynow is down: the pro sends EcoCash to BeauTap's own
/// number, adds the transaction ID, and an admin switches the plan on.
class FeePayScreen extends StatefulWidget {
  final BeauTapFee fee;
  const FeePayScreen({super.key, required this.fee});

  @override
  State<FeePayScreen> createState() => _FeePayScreenState();
}

class _FeePayScreenState extends State<FeePayScreen> {
  bool _loading = true;
  String? _number;
  String? _name;
  Map<String, dynamic>? _pending;
  final _refCtrl = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<dynamic>([
        supabase.from('app_settings').select('key, value').inFilter('key', ['beautap_ecocash_number', 'beautap_ecocash_name']),
        supabase
            .from('fee_claims')
            .select()
            .eq('user_id', supabase.auth.currentUser!.id)
            .eq('purpose', widget.fee.purpose)
            .eq('status', 'claimed')
            .maybeSingle(),
      ]);
      final settings = {for (final r in res[0] as List) r['key']: (r['value'] ?? '').toString()};
      setState(() {
        _number = settings['beautap_ecocash_number'];
        _name = settings['beautap_ecocash_name'];
        _pending = res[1] as Map<String, dynamic>?;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _copy(String text, String what) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) _toast('$what copied');
  }

  Future<void> _submit() async {
    if (_refCtrl.text.trim().length < 4) {
      _toast('Enter the transaction ID from your EcoCash SMS', error: true);
      return;
    }
    setState(() => _sending = true);
    try {
      await supabase.rpc('claim_fee_payment', params: {
        'p_purpose': widget.fee.purpose,
        'p_plan': widget.fee.plan,
        'p_reference': _refCtrl.text.trim(),
      });
      if (!mounted) return;
      _toast('Sent. We\'ll switch it on as soon as we see your payment.');
      context.pop(true);
    } on PostgrestException catch (e) {
      if (mounted) _toast(e.message, error: true);
    } catch (_) {
      if (mounted) _toast('Could not send. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fee = widget.fee;
    final amount = amountText(fee.amount);
    return Scaffold(
      appBar: AppBar(title: const Text('Pay BeauTap')),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : _number == null || _number!.isEmpty
              ? const EmptyState(
                  icon: TablerIcons.device_mobile_off,
                  title: 'Not available right now',
                  message: 'Manual EcoCash payments are switched off. Please pay with Paynow.',
                )
              : _pending != null
                  ? ListView(padding: const EdgeInsets.all(16), children: [
                      SoftBanner(
                        icon: TablerIcons.clock_hour_4,
                        color: AppColors.warning,
                        title: 'We\'re checking your payment',
                        message: 'You sent \$${amountText(_pending!['amount'] as num)} (ref ${_pending!['reference']}). '
                            'We\'ll notify you as soon as it\'s confirmed.',
                      ),
                    ])
                  : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
                      Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(color: AppColors.forest, borderRadius: AppRadius.xlAll),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(fee.label,
                              style: const TextStyle(color: AppColors.goldLight, fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 4),
                          Text('\$${fee.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 36, fontWeight: FontWeight.w800, height: 1.1)),
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.gold,
                                foregroundColor: AppColors.primaryDark,
                                textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                              ),
                              onPressed: () async {
                                final code = '*153*1*1*$_number*$amount#';
                                final ok = await launchUrl(Uri.parse('tel:${Uri.encodeComponent(code)}'));
                                if (!ok) await _copy(code, 'Dial code');
                              },
                              icon: const Icon(TablerIcons.device_mobile, size: 20),
                              label: const Text('Pay with EcoCash'),
                            ),
                          ),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                            color: AppColors.card,
                            borderRadius: AppRadius.mdAll,
                            border: Border.all(color: AppColors.border)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text.rich(
                            TextSpan(children: [
                              const TextSpan(text: 'Send '),
                              TextSpan(text: '\$$amount', style: const TextStyle(fontWeight: FontWeight.w800)),
                              const TextSpan(text: ' to '),
                              TextSpan(text: prettyMobile(_number!), style: const TextStyle(fontWeight: FontWeight.w800)),
                              if ((_name ?? '').isNotEmpty) TextSpan(text: ' ($_name)'),
                            ]),
                            style: const TextStyle(fontSize: 17, height: 1.35),
                          ),
                          const SizedBox(height: 12),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _copy(_number!, 'Number'),
                                icon: const Icon(TablerIcons.copy, size: 18),
                                label: const Text('Copy number'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _copy(amount, 'Amount'),
                                icon: const Icon(TablerIcons.copy, size: 18),
                                label: const Text('Copy amount'),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                      const SizedBox(height: 20),
                      Text('Then add the transaction ID', style: Theme.of(context).textTheme.titleMedium),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _refCtrl,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 60,
                        decoration: const InputDecoration(
                          labelText: 'Transaction ID',
                          hintText: 'From your EcoCash SMS',
                          prefixIcon: Icon(TablerIcons.receipt),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text('We usually confirm within a few hours. You\'ll get a notification.',
                          style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    ]),
      bottomNavigationBar: !_loading && _pending == null && (_number ?? '').isNotEmpty
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed: _sending ? null : _submit,
                  child: Text(_sending ? 'Sending…' : 'I\'ve paid'),
                ),
              ),
            )
          : null,
    );
  }
}
