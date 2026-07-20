import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ProviderProfileEditorScreen extends StatefulWidget {
  const ProviderProfileEditorScreen({super.key});
  @override
  State<ProviderProfileEditorScreen> createState() =>
      _ProviderProfileEditorScreenState();
}

class _ProviderProfileEditorScreenState
    extends State<ProviderProfileEditorScreen> {
  final _formKey     = GlobalKey<FormState>();
  final _bioCtrl     = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lngCtrl     = TextEditingController();
  bool _loading = false;
  bool _saving  = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('provider_profiles')
          .select()
          .eq('provider_id', supabase.auth.currentUser!.id)
          .single();
      _bioCtrl.text     = data['bio']     ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _latCtrl.text     = data['latitude']?.toString()  ?? '';
      _lngCtrl.text     = data['longitude']?.toString() ?? '';
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final userId = supabase.auth.currentUser!.id;
    final payload = {
      'provider_id': userId,
      'bio':         _bioCtrl.text.trim(),
      'address':     _addressCtrl.text.trim(),
      'latitude':    double.tryParse(_latCtrl.text.trim()),
      'longitude':   double.tryParse(_lngCtrl.text.trim()),
    };

    try {
      await supabase
          .from('provider_profiles')
          .upsert(payload, onConflict: 'provider_id');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Profile saved successfully'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
        context.pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _bioCtrl.dispose(); _addressCtrl.dispose();
    _latCtrl.dispose(); _lngCtrl.dispose();
    super.dispose();
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.md),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionDivider() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.xxl),
      child: Divider(color: Colors.grey.shade200, thickness: 1),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Edit Profile')),
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Edit Profile')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // -- Bio Section --
              _buildSectionHeader('About You', Icons.person_outline_rounded),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: Colors.grey.shade200),
                ),
                padding: AppSpacing.cardPadding,
                child: TextFormField(
                  controller: _bioCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Bio',
                    hintText: 'e.g. Professional braider with 5 years experience...',
                    alignLabelWithHint: true,
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    contentPadding: EdgeInsets.zero,
                  ),
                  maxLines: 4,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppColors.textPrimary,
                    height: 1.5,
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Please add a bio' : null,
                ),
              ),

              _buildSectionDivider(),

              // -- Location Section --
              _buildSectionHeader('Location', Icons.location_on_outlined),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Service Area / Address',
                  hintText: 'e.g. Borrowdale, Harare',
                  prefixIcon: Icon(Icons.map_outlined),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Please add your address' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              Row(children: [
                Expanded(
                  child: TextFormField(
                    controller: _latCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      hintText: '-17.8292',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextFormField(
                    controller: _lngCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      hintText: '31.0522',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                  ),
                ),
              ]),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: AppColors.info.withValues(alpha: 0.08),
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        size: 14, color: AppColors.info),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        'Find your coordinates on Google Maps -- right-click your location.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.info,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.xxxl),

              // -- Save Button --
              Container(
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: AppRadius.mdAll,
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_rounded),
                  label: Text(_saving ? 'Saving...' : 'Save Profile'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    disabledBackgroundColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }
}
