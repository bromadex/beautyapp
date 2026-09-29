import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../widgets/ui.dart';

/// Pro referrals: every 2 invited pros who get ID-verified and pay for 2
/// months give the inviter 2 free Pro months (up to 6 a year).
class ReferralsScreen extends StatefulWidget {
  const ReferralsScreen({super.key});

  @override
  State<ReferralsScreen> createState() => _ReferralsScreenState();
}

class _ReferralsScreenState extends State<ReferralsScreen> {
  Map<String, dynamic>? _data;
  String? _error;
  final _codeCtrl = TextEditingController();
  bool _using = false;

  static const _site = 'https://beautyapp-swart.vercel.app';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final d = await supabase.rpc('my_referrals');
      if (mounted) {
        setState(() {
          _data = Map<String, dynamic>.from(d as Map);
          _error = null;
        });
      }
    } on PostgrestException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load referrals. Check your connection.');
    }
  }

  Future<void> _useCode() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() => _using = true);
    try {
      final name = await supabase.rpc('use_referral_code', params: {'p_code': code});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Done. ${name ?? 'Your friend'} invited you.')));
      }
      _codeCtrl.clear();
      await _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _using = false);
    }
  }

  String _inviteText(String code) =>
      'I take bookings on BeauTap, it\'s the easiest way for clients to book and pay me. '
      'Join as a beauty pro with my code $code: $_site/register?ref=$code';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Invite pros')),
      body: _error != null
          ? EmptyState(icon: TablerIcons.users, title: 'Can\'t load referrals', message: _error!, actionLabel: 'Try again', onAction: _load)
          : _data == null
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(onRefresh: _load, child: _body(_data!)),
    );
  }

  Widget _body(Map<String, dynamic> d) {
    final eligible = d['eligible'] == true;
    final paid = (d['payments'] as num?)?.toInt() ?? 0;
    final code = d['code'] as String?;
    final months = (d['months_this_year'] as num?)?.toInt() ?? 0;
    final cap = (d['months_cap'] as num?)?.toInt() ?? 6;
    final list = List<Map<String, dynamic>>.from(d['referrals'] as List? ?? const []);
    final qualified = list.where((r) => r['qualified'] == true && r['rewarded'] != true).length;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.xlAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Invite 2 pros, get 2 months free',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            'When 2 pros you invite are ID-verified and have paid for 2 months, you get 2 free Pro months. '
            'Up to $cap free months a year.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13.5, height: 1.4),
          ),
          const SizedBox(height: 14),
          if (eligible && code != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: AppColors.primaryDark, borderRadius: AppRadius.smAll),
              child: Row(children: [
                const Text('Your code', style: TextStyle(color: AppColors.goldLight, fontSize: 13)),
                const Spacer(),
                Text(code, style: monoStyle.copyWith(color: Colors.white, fontSize: 20, letterSpacing: 2)),
              ]),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: AppColors.gold, foregroundColor: AppColors.primaryDark),
                  onPressed: () => shareOnWhatsApp(_inviteText(code)),
                  icon: const Icon(TablerIcons.brand_whatsapp, size: 20),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: AppColors.goldLight)),
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _inviteText(code)));
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invite copied')));
                    }
                  },
                  icon: const Icon(TablerIcons.copy, size: 18),
                  label: const Text('Copy'),
                ),
              ),
            ]),
          ] else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: AppColors.primaryDark, borderRadius: AppRadius.smAll),
              child: Row(children: [
                const Icon(TablerIcons.lock, color: AppColors.goldLight, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Your code unlocks after your own 2 Pro payments ($paid of 2 so far).',
                    style: const TextStyle(color: Colors.white, fontSize: 13.5),
                  ),
                ),
              ]),
            ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(child: _Stat(label: 'Free months this year', value: '$months of $cap')),
        const SizedBox(width: 8),
        Expanded(child: _Stat(label: 'Counted, not rewarded yet', value: '$qualified')),
      ]),
      const SizedBox(height: 20),
      Text('Pros you invited', style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 8),
      if (list.isEmpty)
        const Text('Nobody yet. Share your code with beauty pros you know.',
            style: TextStyle(color: AppColors.textSecondary))
      else
        Container(
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
          child: Column(children: [
            for (final r in list) _referralRow(r),
          ]),
        ),
      if (d['can_enter_code'] == true) ...[
        const SizedBox(height: 24),
        Text('Were you invited?', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Add the code within 30 days of joining, before your first payment.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(labelText: 'Referral code', prefixIcon: Icon(TablerIcons.ticket)),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 56,
            child: OutlinedButton(onPressed: _using ? null : _useCode, child: const Text('Add')),
          ),
        ]),
      ] else if (d['invited_by'] != null) ...[
        const SizedBox(height: 20),
        Text('You were invited by ${d['invited_by']}.', style: const TextStyle(color: AppColors.textSecondary)),
      ],
    ]);
  }

  Widget _referralRow(Map<String, dynamic> r) {
    final verified = r['verified'] == true;
    final payments = (r['payments'] as num?)?.toInt() ?? 0;
    final (String status, Color color) = r['rewarded'] == true
        ? ('Rewarded', AppColors.success)
        : r['qualified'] == true
            ? ('Counted', AppColors.success)
            : ('In progress', AppColors.warningText);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(children: [
        PersonAvatar(name: r['name'] ?? '', size: 38),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(r['name'] ?? 'New pro', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text('${verified ? 'ID verified' : 'Not verified yet'} · $payments of 2 payments',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ]),
        ),
        Pill(label: status, color: color),
      ]),
    );
  }
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
        ]),
      );
}
