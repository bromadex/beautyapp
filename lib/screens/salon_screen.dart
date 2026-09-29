import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

import '../supabase_client.dart';
import '../theme.dart';
import '../utils/booking_helpers.dart';
import '../widgets/ui.dart';

/// A pro's salon: create or join one, invite staff, see who the $15 salon
/// plan covers (the first 8 people). Every member keeps their own calendar,
/// services and bookings.
class SalonScreen extends StatefulWidget {
  const SalonScreen({super.key});

  @override
  State<SalonScreen> createState() => _SalonScreenState();
}

class _SalonScreenState extends State<SalonScreen> {
  bool _loading = true;
  Map<String, dynamic>? _salon;
  bool _busy = false;

  static const _site = 'https://beautyapp-swart.vercel.app';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final s = await supabase.rpc('my_salon');
      if (mounted) {
        setState(() {
          _salon = s == null ? null : Map<String, dynamic>.from(s as Map);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _run(Future<dynamic> Function() f, {String? done}) async {
    setState(() => _busy = true);
    try {
      await f();
      if (done != null) _toast(done);
      await _load();
    } on PostgrestException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Something went wrong. Try again.', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<(String, String)?> _askNameAddress({String name = '', String address = '', required String title}) {
    final n = TextEditingController(text: name);
    final a = TextEditingController(text: address);
    return showDialog<(String, String)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: n, maxLength: 60, decoration: const InputDecoration(labelText: 'Salon name')),
          TextField(controller: a, maxLength: 120, decoration: const InputDecoration(labelText: 'Area or address (optional)')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => n.text.trim().length < 2 ? null : Navigator.pop(ctx, (n.text.trim(), a.text.trim())),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _create() async {
    final r = await _askNameAddress(title: 'Create your salon');
    if (r == null) return;
    await _run(() => supabase.rpc('create_salon', params: {'p_name': r.$1, 'p_address': r.$2}),
        done: 'Salon created. Invite your team with the code.');
  }

  Future<void> _join() async {
    final c = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a salon'),
        content: TextField(
          controller: c,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(labelText: 'Salon code', hintText: 'Ask the salon owner'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Join')),
        ],
      ),
    );
    if (code == null || code.isEmpty) return;
    await _run(() async {
      final r = Map<String, dynamic>.from(await supabase.rpc('join_salon', params: {'p_code': code}) as Map);
      _toast(r['covered'] == true
          ? 'You joined ${r['salon']}. Their salon plan covers you.'
          : 'You joined ${r['salon']}. Their plan covers 8 people, so you\'ll need your own Pro plan.');
    });
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(action),
            ),
          ],
        ),
      ) ==
      true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Salon')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(onRefresh: _load, child: _salon == null ? _noSalon() : _mySalon(_salon!)),
    );
  }

  Widget _noSalon() {
    return ListView(padding: const EdgeInsets.all(16), children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.xlAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(TablerIcons.building_store, color: AppColors.gold, size: 32),
          const SizedBox(height: 10),
          const Text('One plan for your whole team',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text(
            '\$15 a month covers you and up to 7 staff. Everyone keeps their own calendar, services and '
            'bookings, and clients can find your whole team on one salon page.',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), height: 1.4),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      FilledButton.icon(
        onPressed: _busy ? null : _create,
        icon: const Icon(TablerIcons.plus),
        label: const Text('Create a salon'),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        onPressed: _busy ? null : _join,
        icon: const Icon(TablerIcons.login_2),
        label: const Text('Join with a salon code'),
      ),
    ]);
  }

  Widget _mySalon(Map<String, dynamic> s) {
    final owner = s['is_owner'] == true;
    final active = s['plan_active'] == true;
    final members = List<Map<String, dynamic>>.from(s['members'] as List? ?? const []);
    final code = s['invite_code'] as String?;
    final uid = supabase.auth.currentUser?.id;
    final me = members.where((m) => m['id'] == uid).firstOrNull;
    final mySeat = (me?['seat'] as num?)?.toInt() ?? 1;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.xlAll),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(s['name'] ?? '',
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800)),
            ),
            if (owner)
              IconButton(
                onPressed: _busy
                    ? null
                    : () async {
                        final r = await _askNameAddress(
                            title: 'Edit salon', name: s['name'] ?? '', address: s['address'] ?? '');
                        if (r != null) {
                          await _run(() => supabase.rpc('update_salon', params: {'p_name': r.$1, 'p_address': r.$2}),
                              done: 'Saved');
                        }
                      },
                icon: const Icon(TablerIcons.pencil, color: AppColors.goldLight),
              ),
          ]),
          if ((s['address'] ?? '').toString().isNotEmpty)
            Text(s['address'], style: TextStyle(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 12),
          Row(children: [
            Pill(
              label: active ? 'Salon plan active' : 'No salon plan',
              color: active ? AppColors.goldLight : Colors.white,
              icon: active ? TablerIcons.circle_check : TablerIcons.alert_circle,
            ),
            const Spacer(),
            Text('${members.length} ${members.length == 1 ? 'person' : 'people'}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
          ]),
        ]),
      ),
      const SizedBox(height: 12),
      if (owner && !active)
        SoftBanner(
          icon: TablerIcons.crown,
          color: AppColors.primary,
          title: 'Pay the \$15 salon plan',
          message: 'Covers you and the next 7 people who join. Pay it on the Your plan page.',
          actionLabel: 'Open',
          onTap: () => context.push('/provider/subscription').then((_) => _load()),
        )
      else if (!owner)
        SoftBanner(
          icon: mySeat <= 8 && active ? TablerIcons.circle_check : TablerIcons.alert_circle,
          color: mySeat <= 8 && active ? AppColors.success : AppColors.warning,
          title: mySeat <= 8 && active
              ? 'The salon plan covers you'
              : mySeat > 8
                  ? 'You need your own Pro plan'
                  : 'The salon plan isn\'t active',
          message: mySeat > 8
              ? 'The salon plan covers the first 8 people. You\'re number $mySeat.'
              : active
                  ? 'You don\'t need to pay for Pro yourself.'
                  : 'Ask the owner to pay it, or use your own Pro plan.',
        ),
      if (owner && code != null) ...[
        const SizedBox(height: 16),
        Text('Invite your team', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        const Text('Staff sign up as beauty pros, then join with this code.',
            style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Text(code, style: monoStyle.copyWith(fontSize: 22, color: AppColors.textPrimary, letterSpacing: 2)),
            const Spacer(),
            IconButton(
              tooltip: 'Copy',
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: code));
                _toast('Code copied');
              },
              icon: const Icon(TablerIcons.copy),
            ),
            IconButton(
              tooltip: 'Share on WhatsApp',
              onPressed: () => shareOnWhatsApp(
                  'Join ${s['name']} on BeauTap. Sign up as a beauty pro at $_site/register, then go to '
                  'Me > Salon > Join and enter code $code.'),
              icon: const Icon(TablerIcons.brand_whatsapp, color: Color(0xFF25D366)),
            ),
            IconButton(
              tooltip: 'New code',
              onPressed: _busy ? null : () => _run(() => supabase.rpc('new_salon_invite_code'), done: 'New code made. The old one no longer works.'),
              icon: const Icon(TablerIcons.refresh),
            ),
          ]),
        ),
      ],
      const SizedBox(height: 20),
      Row(children: [
        Expanded(child: Text('Team', style: Theme.of(context).textTheme.titleMedium)),
        TextButton.icon(
          onPressed: () => context.push('/salon/${s['id']}'),
          icon: const Icon(TablerIcons.eye, size: 18),
          label: const Text('Salon page'),
        ),
      ]),
      const SizedBox(height: 4),
      Container(
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
        child: Column(children: [
          for (final m in members) _memberRow(m, owner: owner, active: active),
        ]),
      ),
      const SizedBox(height: 24),
      if (owner)
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirm('Close ${s['name']}?',
                      'Everyone leaves the salon. Staff keep their own accounts, but the salon plan stops covering them.',
                      'Close salon')) {
                    await _run(() => supabase.rpc('close_salon'), done: 'Salon closed');
                  }
                },
          child: const Text('Close salon', style: TextStyle(color: AppColors.error)),
        )
      else
        TextButton(
          onPressed: _busy
              ? null
              : () async {
                  if (await _confirm('Leave ${s['name']}?', 'The salon plan will stop covering you.', 'Leave')) {
                    await _run(() => supabase.rpc('leave_salon'), done: 'You left the salon');
                  }
                },
          child: const Text('Leave salon', style: TextStyle(color: AppColors.error)),
        ),
    ]);
  }

  Widget _memberRow(Map<String, dynamic> m, {required bool owner, required bool active}) {
    final seat = (m['seat'] as num?)?.toInt() ?? 1;
    final covered = seat <= 8;
    final isOwner = m['role'] == 'owner';
    final String status = isOwner
        ? 'Owner'
        : covered
            ? (active ? 'Covered by salon plan' : 'Seat $seat of 8')
            : (m['own_plan'] == true ? 'Own Pro plan' : 'Needs own Pro plan');
    return ListTile(
      leading: PersonAvatar(name: m['name'] ?? '', url: m['avatar_url'], size: 40),
      title: Text(m['name'] ?? 'Pro', style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(status,
          style: TextStyle(color: !covered && m['own_plan'] != true ? AppColors.warningText : AppColors.textSecondary)),
      trailing: owner && !isOwner
          ? IconButton(
              tooltip: 'Remove',
              icon: const Icon(TablerIcons.user_minus, color: AppColors.textTertiary),
              onPressed: _busy
                  ? null
                  : () async {
                      if (await _confirm('Remove ${m['name']}?', 'They keep their account but leave the salon.', 'Remove')) {
                        await _run(() => supabase.rpc('remove_salon_member', params: {'p_provider': m['id']}),
                            done: 'Removed');
                      }
                    },
            )
          : null,
      onTap: () => context.push('/provider/${m['id']}'),
    );
  }
}
