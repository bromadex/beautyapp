import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/pay_methods.dart';
import '../widgets/ui.dart';

/// Admin: EcoCash payments pros sent to BeauTap by hand (the backup for
/// when Paynow is down), and the BeauTap number they send to.
class AdminFeesScreen extends StatefulWidget {
  const AdminFeesScreen({super.key});

  @override
  State<AdminFeesScreen> createState() => _AdminFeesScreenState();
}

class _AdminFeesScreenState extends State<AdminFeesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _claims = [];
  final _numberCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  bool _savingNumber = false;
  final Set<String> _busy = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final res = await Future.wait<dynamic>([
        supabase
            .from('fee_claims')
            .select('*, profiles!fee_claims_user_id_fkey(full_name, phone)')
            .order('created_at', ascending: false)
            .limit(100),
        supabase.from('app_settings').select('key, value').inFilter('key', ['beautap_ecocash_number', 'beautap_ecocash_name']),
      ]);
      final settings = {for (final r in res[1] as List) r['key']: (r['value'] ?? '').toString()};
      if (!mounted) return;
      setState(() {
        _claims = List<Map<String, dynamic>>.from(res[0] as List);
        _numberCtrl.text = settings['beautap_ecocash_number'] ?? '';
        _nameCtrl.text = settings['beautap_ecocash_name'] ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _saveNumber() async {
    final n = normalizeZimMobile(_numberCtrl.text);
    if (n == '') {
      _toast('That doesn\'t look like an EcoCash number', error: true);
      return;
    }
    setState(() => _savingNumber = true);
    try {
      await supabase.from('app_settings').upsert([
        {'key': 'beautap_ecocash_number', 'value': n ?? '', 'updated_at': DateTime.now().toUtc().toIso8601String()},
        {'key': 'beautap_ecocash_name', 'value': _nameCtrl.text.trim(), 'updated_at': DateTime.now().toUtc().toIso8601String()},
      ]);
      _numberCtrl.text = n ?? '';
      _toast(n == null ? 'Manual EcoCash payments switched off' : 'Saved. Pros can now pay by EcoCash if Paynow is down.');
    } catch (_) {
      _toast('Could not save', error: true);
    } finally {
      if (mounted) setState(() => _savingNumber = false);
    }
  }

  Future<void> _decide(Map<String, dynamic> c, bool approve) async {
    String? note;
    if (!approve) {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Payment not found?'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(labelText: 'Note to the pro (optional)', hintText: 'e.g. Amount was \$3, not \$5'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Reject')),
          ],
        ),
      );
      if (ok != true) return;
      note = ctrl.text.trim();
    }
    setState(() => _busy.add(c['id']));
    try {
      await supabase.rpc('review_fee_claim', params: {'p_claim': c['id'], 'p_approve': approve, 'p_note': note});
      _toast(approve ? 'Approved and switched on' : 'Rejected. The pro was told.');
      await _load();
    } on PostgrestException catch (e) {
      _toast(e.message, error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(c['id']));
    }
  }

  String _what(Map c) => switch (c['purpose']) {
        'featured' => 'Featured week',
        'product_pack' => 'Product pack',
        _ => switch (c['plan']) { 'salon' => 'Salon plan', 'activation' => 'Pro activation', _ => 'Pro plan' },
      };

  @override
  Widget build(BuildContext context) {
    final open = _claims.where((c) => c['status'] == 'claimed').toList();
    final done = _claims.where((c) => c['status'] != 'claimed').toList();
    return Scaffold(
      appBar: AppBar(title: const Text('EcoCash fee payments')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(padding: const EdgeInsets.all(16), children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('BeauTap EcoCash number', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 4),
                    const Text('Pros see this as a backup when Paynow is down. Leave empty to switch it off.',
                        style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _numberCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(labelText: 'EcoCash number', prefixIcon: Icon(TablerIcons.device_mobile)),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(labelText: 'Name on the account', prefixIcon: Icon(TablerIcons.user)),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(onPressed: _savingNumber ? null : _saveNumber, child: const Text('Save')),
                  ]),
                ),
                const SizedBox(height: 20),
                Text('To check (${open.length})', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (open.isEmpty)
                  const Text('Nothing to check.', style: TextStyle(color: AppColors.textSecondary))
                else
                  for (final c in open) _claimCard(c, actions: true),
                if (done.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Recent', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  for (final c in done.take(30)) _claimCard(c, actions: false),
                ],
              ]),
            ),
    );
  }

  Widget _claimCard(Map<String, dynamic> c, {required bool actions}) {
    final p = c['profiles'] as Map?;
    final when = DateTime.tryParse(c['created_at'] ?? '')?.toLocal();
    final busy = _busy.contains(c['id']);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: actions ? AppColors.warningSoft : Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: actions ? AppColors.warning.withValues(alpha: 0.4) : AppColors.border),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('${p?['full_name'] ?? 'Pro'} · ${_what(c)}', style: const TextStyle(fontWeight: FontWeight.w800)),
          ),
          Text('\$${amountText(c['amount'] as num)}', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Text('Ref ', style: const TextStyle(color: AppColors.textSecondary)),
          SelectableText('${c['reference']}', style: monoStyle.copyWith(color: AppColors.textPrimary)),
          const Spacer(),
          if (!actions) StatusPill(c['status'] == 'approved' ? 'completed' : 'cancelled',
              label: c['status'] == 'approved' ? 'Approved' : 'Rejected'),
        ]),
        if (when != null || p?['phone'] != null)
          Text(
            [
              if (when != null)
                '${when.day}/${when.month} ${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}',
              if (p?['phone'] != null) '${p!['phone']}',
            ].join(' · '),
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
          ),
        if (actions) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(onPressed: busy ? null : () => _decide(c, false), child: const Text('Not found')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(onPressed: busy ? null : () => _decide(c, true), child: const Text('Received')),
            ),
          ]),
        ],
      ]),
    );
  }
}
