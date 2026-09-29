import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import 'package:url_launcher/url_launcher.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/pay_methods.dart';
import '../widgets/certificates_section.dart';

class ProviderSettingsScreen extends StatefulWidget {
  const ProviderSettingsScreen({super.key});

  @override
  State<ProviderSettingsScreen> createState() => _ProviderSettingsScreenState();
}

class _ProviderSettingsScreenState extends State<ProviderSettingsScreen> {
  bool _loading = true;
  bool _saving = false;

  // Travel fees
  final _travelFeeCtrl = TextEditingController(text: '0');
  final _freeRadiusCtrl = TextEditingController(text: '5');
  final _maxTravelFeeCtrl = TextEditingController(text: '20');

  // Buffer time
  final _bufferCtrl = TextEditingController(text: '0');

  // Booking rules
  final _noticeCtrl = TextEditingController(text: '2');
  final _advanceCtrl = TextEditingController(text: '60');
  final _depositCtrl = TextEditingController(text: '0');

  // How clients pay you
  bool _acceptsCash = true;
  final _ecocashCtrl = TextEditingController();
  final _ecocashNameCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  final _innbucksCtrl = TextEditingController();
  final _onemoneyCtrl = TextEditingController();
  final _bankCtrl = TextEditingController();
  final _payNoteCtrl = TextEditingController();

  // Cancellation policy
  final _freeCancelCtrl = TextEditingController(text: '24');
  final _lateCancelCtrl = TextEditingController(text: '50');
  final _noShowCtrl = TextEditingController(text: '100');
  final _policyTextCtrl = TextEditingController();

  // Business verification
  final _bizNameCtrl = TextEditingController();
  final _bizRegCtrl = TextEditingController();
  Map<String, dynamic>? _bizVerification;
  bool _bizVerified = false;
  bool _submittingBiz = false;

  // Booking link + loyalty
  final _slugCtrl = TextEditingController();
  String _savedSlug = '';
  int _loyaltyVisits = 0;
  final _loyaltyPctCtrl = TextEditingController(text: '10');

  static const _siteUrl = 'https://beautyapp-swart.vercel.app';
  String get _link => '$_siteUrl/@$_savedSlug';

  // WhatsApp
  final _whatsappCtrl = TextEditingController();
  String _preferredContact = 'in_app';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;

    try {
      final pp = await supabase
          .from('provider_profiles')
          .select()
          .eq('provider_id', uid)
          .maybeSingle();

      if (pp != null) {
        _travelFeeCtrl.text = '${pp['travel_fee_per_km'] ?? 0}';
        _freeRadiusCtrl.text = '${pp['free_travel_radius_km'] ?? 5}';
        _maxTravelFeeCtrl.text = '${pp['max_travel_fee'] ?? 20}';
        _bufferCtrl.text = '${pp['buffer_minutes'] ?? 0}';
        _noticeCtrl.text = '${pp['min_notice_hours'] ?? 2}';
        _advanceCtrl.text = '${pp['max_advance_days'] ?? 60}';
        _depositCtrl.text = '${pp['deposit_percent'] ?? 0}';
        _acceptsCash = pp['accepts_cash'] != false;
        _ecocashCtrl.text = pp['ecocash_number'] ?? '';
        _ecocashNameCtrl.text = pp['ecocash_name'] ?? '';
        _merchantCtrl.text = pp['ecocash_merchant'] ?? '';
        _innbucksCtrl.text = pp['innbucks_number'] ?? '';
        _onemoneyCtrl.text = pp['onemoney_number'] ?? '';
        _bankCtrl.text = pp['bank_details'] ?? '';
        _payNoteCtrl.text = pp['pay_note'] ?? '';
        _preferredContact = pp['preferred_contact'] ?? 'in_app';
        _savedSlug = pp['slug'] ?? '';
        _slugCtrl.text = _savedSlug;
        _loyaltyVisits = (pp['loyalty_visits'] as num?)?.toInt() ?? 0;
        final pct = (pp['loyalty_percent'] as num?)?.toInt() ?? 0;
        if (pct > 0) _loyaltyPctCtrl.text = '$pct';
      }

      final policy = await supabase
          .from('cancellation_policies')
          .select()
          .eq('provider_id', uid)
          .maybeSingle();

      if (policy != null) {
        _freeCancelCtrl.text = '${policy['free_cancel_hours'] ?? 24}';
        _lateCancelCtrl.text = '${policy['late_cancel_fee_percent'] ?? 50}';
        _noShowCtrl.text = '${policy['no_show_fee_percent'] ?? 100}';
        _policyTextCtrl.text = policy['policy_text'] ?? '';
      }

      final profile = await supabase
          .from('profiles')
          .select('whatsapp_number, is_business_verified')
          .eq('id', uid)
          .maybeSingle();
      _whatsappCtrl.text = profile?['whatsapp_number'] ?? '';
      _bizVerified = profile?['is_business_verified'] == true;

      _bizVerification = await supabase
          .from('business_verifications')
          .select()
          .eq('provider_id', uid)
          .maybeSingle();
      _bizNameCtrl.text = _bizVerification?['business_name'] ?? '';
      _bizRegCtrl.text = _bizVerification?['registration_number'] ?? '';
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  void _snack(String msg) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(msg), backgroundColor: AppColors.error));

  String? _text(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  bool get _takesTransfers => [_ecocashCtrl, _merchantCtrl, _innbucksCtrl, _onemoneyCtrl, _bankCtrl]
      .any((c) => c.text.trim().isNotEmpty);

  Future<void> _save() async {
    final uid = supabase.auth.currentUser!.id;

    // Check the payment numbers before saving anything.
    final numbers = <String, String?>{};
    for (final (key, label, ctrl) in [
      ('ecocash_number', 'EcoCash', _ecocashCtrl),
      ('innbucks_number', 'InnBucks', _innbucksCtrl),
      ('onemoney_number', 'OneMoney', _onemoneyCtrl),
    ]) {
      final n = normalizeZimMobile(ctrl.text);
      if (n == '') {
        _snack('Your $label number doesn\'t look right. Use a number like 077 123 4567.');
        return;
      }
      numbers[key] = n;
      if (n != null) ctrl.text = n;
    }
    final merchant = _merchantCtrl.text.replaceAll(RegExp(r'\s'), '');
    if (merchant.isNotEmpty && !RegExp(r'^\d{3,10}$').hasMatch(merchant)) {
      _snack('A merchant code is numbers only.');
      return;
    }
    if (!_acceptsCash && !_takesTransfers) {
      _snack('Add at least one way for clients to pay you.');
      return;
    }

    setState(() => _saving = true);

    try {
      final slug = _slugCtrl.text.trim().toLowerCase();
      if (slug.isNotEmpty && slug != _savedSlug) {
        await supabase.from('provider_profiles').update({'slug': slug}).eq('provider_id', uid);
        _savedSlug = slug;
      }
      await supabase.from('provider_profiles').update({
        'loyalty_visits': _loyaltyVisits,
        'loyalty_percent': _loyaltyVisits == 0 ? 0 : (int.tryParse(_loyaltyPctCtrl.text) ?? 10).clamp(1, 100),
        'travel_fee_per_km': double.tryParse(_travelFeeCtrl.text) ?? 0,
        'free_travel_radius_km': double.tryParse(_freeRadiusCtrl.text) ?? 5,
        'max_travel_fee': double.tryParse(_maxTravelFeeCtrl.text) ?? 20,
        'buffer_minutes': int.tryParse(_bufferCtrl.text) ?? 0,
        'min_notice_hours': (int.tryParse(_noticeCtrl.text) ?? 2).clamp(0, 168),
        'max_advance_days': (int.tryParse(_advanceCtrl.text) ?? 60).clamp(1, 365),
        'deposit_percent': (int.tryParse(_depositCtrl.text) ?? 0).clamp(0, 100),
        'preferred_contact': _preferredContact,
        'accepts_cash': _acceptsCash,
        ...numbers,
        'ecocash_merchant': merchant.isEmpty ? null : merchant,
        'ecocash_name': _text(_ecocashNameCtrl),
        'bank_details': _text(_bankCtrl),
        'pay_note': _text(_payNoteCtrl),
      }).eq('provider_id', uid);

      await supabase.from('cancellation_policies').upsert({
        'provider_id': uid,
        'free_cancel_hours': int.tryParse(_freeCancelCtrl.text) ?? 24,
        'late_cancel_fee_percent': int.tryParse(_lateCancelCtrl.text) ?? 50,
        'no_show_fee_percent': int.tryParse(_noShowCtrl.text) ?? 100,
        'policy_text': _policyTextCtrl.text.trim().isEmpty
            ? null
            : _policyTextCtrl.text.trim(),
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'provider_id');

      await supabase.from('profiles').update({
        'whatsapp_number': _whatsappCtrl.text.trim().isEmpty
            ? null
            : _whatsappCtrl.text.trim(),
      }).eq('id', uid);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Settings saved'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _buildLinkSection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Put this in your WhatsApp status, Instagram bio or Facebook page. Clients tap it and book you directly.',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _slugCtrl,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
          LengthLimitingTextInputFormatter(30),
        ],
        decoration: InputDecoration(
          labelText: 'Link name',
          prefixText: 'beautyapp-swart.vercel.app/@',
          border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
          isDense: true,
        ),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text('Letters, numbers and dashes. Tap Save to change it.',
          style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      if (_savedSlug.isNotEmpty) ...[
        const SizedBox(height: AppSpacing.md),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _link));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Link copied')));
                }
              },
              icon: const Icon(TablerIcons.copy, size: 18),
              label: const Text('Copy link'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: FilledButton.icon(
              onPressed: () => launchUrl(
                Uri.parse('https://wa.me/?text=${Uri.encodeComponent('Book me on BeauTap: $_link')}'),
                mode: LaunchMode.externalApplication,
              ),
              icon: const Icon(TablerIcons.share_2, size: 18),
              label: const Text('WhatsApp'),
            ),
          ),
        ]),
      ],
    ]);
  }

  Widget _buildLoyaltySection() {
    final on = _loyaltyVisits > 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Reward regulars. You choose the reward and you fund it, so it comes off your price, not BeauTap\'s.',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Stamp card'),
        subtitle: Text(on ? 'On' : 'Off'),
        value: on,
        onChanged: (v) => setState(() => _loyaltyVisits = v ? 5 : 0),
      ),
      if (on) ...[
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _loyaltyVisits,
              decoration: InputDecoration(
                labelText: 'Reward on visit',
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                isDense: true,
              ),
              items: [for (var n = 2; n <= 20; n++) DropdownMenuItem(value: n, child: Text('Every ${_ordinal(n)} visit'))],
              onChanged: (v) => setState(() => _loyaltyVisits = v ?? 5),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: _NumberField(controller: _loyaltyPctCtrl, label: 'Discount', suffix: '% off')),
        ]),
        const SizedBox(height: AppSpacing.xs),
        Text('After ${_loyaltyVisits - 1} completed visits with you, the client\'s next booking gets the discount automatically.',
            style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
      ],
    ]);
  }

  static String _ordinal(int n) {
    if (n >= 11 && n <= 13) return '${n}th';
    return switch (n % 10) { 1 => '${n}st', 2 => '${n}nd', 3 => '${n}rd', _ => '${n}th' };
  }

  Future<void> _submitBusiness() async {
    if (_bizNameCtrl.text.trim().isEmpty || _bizRegCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Enter your business name and registration number')));
      return;
    }
    setState(() => _submittingBiz = true);
    try {
      final row = await supabase.from('business_verifications').upsert({
        'provider_id': supabase.auth.currentUser!.id,
        'business_name': _bizNameCtrl.text.trim(),
        'registration_number': _bizRegCtrl.text.trim(),
        'status': 'pending',
      }, onConflict: 'provider_id').select().single();
      if (mounted) {
        setState(() => _bizVerification = row);
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Submitted — we\'ll review it within 2 working days')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
      }
    } finally {
      if (mounted) setState(() => _submittingBiz = false);
    }
  }

  Widget _buildBusinessSection() {
    final status = _bizVerification?['status'];
    if (_bizVerified) {
      return _StatusNote(
        icon: TablerIcons.rosette_discount_check,
        color: AppColors.success,
        text: 'Your business is verified. Clients see a Verified Business badge on your profile.',
      );
    }
    if (status == 'pending') {
      return _StatusNote(
        icon: TablerIcons.hourglass_high,
        color: AppColors.warning,
        text: 'Submitted for review: ${_bizVerification?['business_name'] ?? ''}. We\'ll notify you once it\'s checked.',
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (status == 'rejected')
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _StatusNote(
            icon: TablerIcons.info_circle,
            color: AppColors.error,
            text: 'Not approved${_bizVerification?['admin_notes'] != null ? ': ${_bizVerification!['admin_notes']}' : ''}. You can correct the details and resubmit.',
          ),
        ),
      Text('Registered salons and businesses can get a Verified Business badge.',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _bizNameCtrl,
        decoration: InputDecoration(
          labelText: 'Registered business name',
          border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
          isDense: true,
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      TextField(
        controller: _bizRegCtrl,
        decoration: InputDecoration(
          labelText: 'Company registration number',
          border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
          isDense: true,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      OutlinedButton(
        onPressed: _submittingBiz ? null : _submitBusiness,
        child: Text(_submittingBiz ? 'Submitting…' : 'Submit for Verification'),
      ),
    ]);
  }

  @override
  void dispose() {
    _bizNameCtrl.dispose();
    _bizRegCtrl.dispose();
    _travelFeeCtrl.dispose();
    _freeRadiusCtrl.dispose();
    _maxTravelFeeCtrl.dispose();
    _bufferCtrl.dispose();
    _noticeCtrl.dispose();
    _advanceCtrl.dispose();
    _depositCtrl.dispose();
    for (final c in [_ecocashCtrl, _ecocashNameCtrl, _merchantCtrl, _innbucksCtrl, _onemoneyCtrl, _bankCtrl, _payNoteCtrl]) {
      c.dispose();
    }
    _freeCancelCtrl.dispose();
    _lateCancelCtrl.dispose();
    _noShowCtrl.dispose();
    _policyTextCtrl.dispose();
    _whatsappCtrl.dispose();
    _slugCtrl.dispose();
    _loyaltyPctCtrl.dispose();
    super.dispose();
  }

  Widget _payField(TextEditingController c, String label, IconData icon,
      {String? hint, TextInputType type = TextInputType.phone, int maxLines = 1, int? maxLength}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: c,
        keyboardType: type,
        maxLines: maxLines,
        maxLength: maxLength,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
          isDense: true,
        ),
      ),
    );
  }

  Widget _buildPaySection() {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Clients pay you directly. BeauTap never touches your money.',
          style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
      const SizedBox(height: AppSpacing.md),
      _payField(_ecocashCtrl, 'EcoCash number', TablerIcons.device_mobile, hint: '077 123 4567'),
      _payField(_ecocashNameCtrl, 'Name on your EcoCash account', TablerIcons.user,
          hint: 'So clients know it\'s you', type: TextInputType.name, maxLength: 60),
      _payField(_merchantCtrl, 'EcoCash merchant code (optional)', TablerIcons.building_store,
          type: TextInputType.number),
      _payField(_innbucksCtrl, 'InnBucks number (optional)', TablerIcons.wallet),
      _payField(_onemoneyCtrl, 'OneMoney number (optional)', TablerIcons.device_mobile_dollar),
      _payField(_bankCtrl, 'Bank details (optional)', TablerIcons.building_bank,
          hint: 'Bank, account name, account number', type: TextInputType.multiline, maxLines: 3, maxLength: 300),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _acceptsCash,
        onChanged: (v) => setState(() => _acceptsCash = v),
        title: const Text('I take cash'),
        subtitle: const Text('Clients can pay you in cash at the appointment'),
      ),
      _payField(_payNoteCtrl, 'Note for clients (optional)', TablerIcons.notes,
          hint: 'e.g. Use your booking reference as the payment note',
          type: TextInputType.text, maxLength: 200),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Business Settings'),
        actions: [
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    height: 18,
                    width: 18,
                    child:
                        CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _SectionHeader(icon: TablerIcons.link, title: 'Your Booking Link'),
            const SizedBox(height: AppSpacing.sm),
            _buildLinkSection(),
            const SizedBox(height: AppSpacing.xxl),
            _SectionHeader(icon: TablerIcons.gift, title: 'Loyalty Reward'),
            const SizedBox(height: AppSpacing.sm),
            _buildLoyaltySection(),
            const SizedBox(height: AppSpacing.xxl),
            _SectionHeader(icon: TablerIcons.wallet, title: 'How Clients Pay You'),
            const SizedBox(height: AppSpacing.sm),
            _buildPaySection(),
            const SizedBox(height: AppSpacing.xxl),
            _SectionHeader(
              icon: TablerIcons.list_check,
              title: 'Booking Rules',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Clients only see times that fit these rules.',
                style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.md),
            Row(children: [
              Expanded(
                child: _NumberField(
                  controller: _noticeCtrl,
                  label: 'Min. notice',
                  suffix: 'hours',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  controller: _advanceCtrl,
                  label: 'Book up to',
                  suffix: 'days ahead',
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            _NumberField(
              controller: _depositCtrl,
              label: 'Deposit to secure a booking (0 = none)',
              suffix: '%',
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
                _takesTransfers
                    ? 'Clients send the deposit straight to you after they book. It cuts no-shows.'
                    : 'Add EcoCash or another way to pay you above, so clients can send a deposit.',
                style: TextStyle(
                    fontSize: 12,
                    color: _takesTransfers || (int.tryParse(_depositCtrl.text) ?? 0) == 0
                        ? AppColors.textTertiary
                        : AppColors.warningText)),

            const SizedBox(height: AppSpacing.xxl),

            // Travel Fees
            _SectionHeader(
              icon: TablerIcons.car,
              title: 'Travel Fees',
            ),
            const SizedBox(height: AppSpacing.md),
            _NumberField(
              controller: _travelFeeCtrl,
              label: 'Fee per km (\$)',
              suffix: '/km',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: _NumberField(
                  controller: _freeRadiusCtrl,
                  label: 'Free radius (km)',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  controller: _maxTravelFeeCtrl,
                  label: 'Max fee (\$)',
                ),
              ),
            ]),

            const SizedBox(height: AppSpacing.xxl),

            // Buffer Time
            _SectionHeader(
              icon: TablerIcons.clock_hour_4,
              title: 'Buffer Time',
            ),
            const SizedBox(height: AppSpacing.sm),
            Text('Minutes between appointments',
                style: TextStyle(
                    fontSize: 13, color: AppColors.textTertiary)),
            const SizedBox(height: AppSpacing.sm),
            _NumberField(
              controller: _bufferCtrl,
              label: 'Buffer (minutes)',
              suffix: 'min',
            ),

            const SizedBox(height: AppSpacing.xxl),

            // Cancellation Policy
            _SectionHeader(
              icon: TablerIcons.calendar_x,
              title: 'Cancellation Policy',
            ),
            const SizedBox(height: AppSpacing.md),
            _NumberField(
              controller: _freeCancelCtrl,
              label: 'Free cancel window (hours)',
              suffix: 'hours',
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(children: [
              Expanded(
                child: _NumberField(
                  controller: _lateCancelCtrl,
                  label: 'Late cancel fee (%)',
                  suffix: '%',
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _NumberField(
                  controller: _noShowCtrl,
                  label: 'No-show fee (%)',
                  suffix: '%',
                ),
              ),
            ]),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _policyTextCtrl,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Policy text (optional)',
                hintText: 'Describe your cancellation policy to clients...',
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
              ),
            ),

            const SizedBox(height: AppSpacing.xxl),

            // WhatsApp & Contact
            _SectionHeader(
              icon: TablerIcons.message_circle,
              title: 'Contact Preferences',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _whatsappCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'WhatsApp Number',
                hintText: '+263 7X XXX XXXX',
                prefixIcon: const Icon(TablerIcons.device_mobile),
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text('Preferred contact method',
                style: Theme.of(context).textTheme.labelMedium),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                ChoiceChip(
                  label: const Text('In-App'),
                  selected: _preferredContact == 'in_app',
                  onSelected: (_) =>
                      setState(() => _preferredContact = 'in_app'),
                ),
                ChoiceChip(
                  label: const Text('WhatsApp'),
                  selected: _preferredContact == 'whatsapp',
                  onSelected: (_) =>
                      setState(() => _preferredContact = 'whatsapp'),
                ),
                ChoiceChip(
                  label: const Text('Both'),
                  selected: _preferredContact == 'both',
                  onSelected: (_) =>
                      setState(() => _preferredContact = 'both'),
                ),
              ],
            ),

            const SizedBox(height: AppSpacing.xxl),

            _SectionHeader(
              icon: TablerIcons.building_store,
              title: 'Business Verification',
            ),
            const SizedBox(height: AppSpacing.md),
            _buildBusinessSection(),

            const SizedBox(height: AppSpacing.xxl),
            _SectionHeader(icon: TablerIcons.certificate, title: 'Certificates'),
            const SizedBox(height: AppSpacing.md),
            const CertificatesSection(),

            const SizedBox(height: AppSpacing.xxxl),

            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      height: 22,
                      width: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Text('Save Settings'),
            ),
            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: AppRadius.smAll,
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
      const SizedBox(width: AppSpacing.md),
      Text(title, style: Theme.of(context).textTheme.titleMedium),
    ]);
  }
}

class _NumberField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? suffix;

  const _NumberField({
    required this.controller,
    required this.label,
    this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
        isDense: true,
      ),
    );
  }
}

class _StatusNote extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;
  const _StatusNote({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
      ]),
    );
  }
}
