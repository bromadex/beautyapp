import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

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

  // Cancellation policy
  final _freeCancelCtrl = TextEditingController(text: '24');
  final _lateCancelCtrl = TextEditingController(text: '50');
  final _noShowCtrl = TextEditingController(text: '100');
  final _policyTextCtrl = TextEditingController();

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
        _preferredContact = pp['preferred_contact'] ?? 'in_app';
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
          .select('whatsapp_number')
          .eq('id', uid)
          .maybeSingle();
      _whatsappCtrl.text = profile?['whatsapp_number'] ?? '';
    } catch (_) {}

    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final uid = supabase.auth.currentUser!.id;

    try {
      await supabase.from('provider_profiles').update({
        'travel_fee_per_km': double.tryParse(_travelFeeCtrl.text) ?? 0,
        'free_travel_radius_km': double.tryParse(_freeRadiusCtrl.text) ?? 5,
        'max_travel_fee': double.tryParse(_maxTravelFeeCtrl.text) ?? 20,
        'buffer_minutes': int.tryParse(_bufferCtrl.text) ?? 0,
        'preferred_contact': _preferredContact,
      }).eq('provider_id', uid);

      await supabase.from('cancellation_policies').upsert({
        'provider_id': uid,
        'free_cancel_hours': int.tryParse(_freeCancelCtrl.text) ?? 24,
        'late_cancel_fee_percent': int.tryParse(_lateCancelCtrl.text) ?? 50,
        'no_show_fee_percent': int.tryParse(_noShowCtrl.text) ?? 100,
        'policy_text': _policyTextCtrl.text.trim().isEmpty
            ? null
            : _policyTextCtrl.text.trim(),
        'updated_at': DateTime.now().toIso8601String(),
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

  @override
  void dispose() {
    _travelFeeCtrl.dispose();
    _freeRadiusCtrl.dispose();
    _maxTravelFeeCtrl.dispose();
    _bufferCtrl.dispose();
    _freeCancelCtrl.dispose();
    _lateCancelCtrl.dispose();
    _noShowCtrl.dispose();
    _policyTextCtrl.dispose();
    _whatsappCtrl.dispose();
    super.dispose();
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
            // Travel Fees
            _SectionHeader(
              icon: Icons.directions_car_outlined,
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
              icon: Icons.timer_outlined,
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
              icon: Icons.event_busy_outlined,
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
              icon: Icons.chat_outlined,
              title: 'Contact Preferences',
            ),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _whatsappCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: 'WhatsApp Number',
                hintText: '+263 7X XXX XXXX',
                prefixIcon: const Icon(Icons.phone_android_rounded),
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
