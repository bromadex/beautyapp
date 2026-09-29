import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';
import '../services/location_service.dart';

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
  final _titleCtrl   = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lngCtrl     = TextEditingController();
  double _radiusKm = 10;
  bool _radiusSupported = true;
  bool _loading = false;
  bool _saving  = false;
  bool _locating = false;
  String? _avatarUrl;
  String _fullName = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) Navigator.of(context).pop();
        return;
      }
      final profile = await supabase
          .from('profiles')
          .select('full_name, avatar_url')
          .eq('id', uid)
          .maybeSingle();
      _fullName = profile?['full_name'] ?? '';
      _avatarUrl = profile?['avatar_url'];

      final data = await supabase
          .from('provider_profiles')
          .select()
          .eq('provider_id', uid)
          .single();
      _bioCtrl.text     = data['bio']     ?? '';
      _titleCtrl.text   = data['title']   ?? '';
      _addressCtrl.text = data['address'] ?? '';
      _latCtrl.text     = data['latitude']?.toString()  ?? '';
      _lngCtrl.text     = data['longitude']?.toString() ?? '';
      if (data.containsKey('service_radius_km')) {
        _radiusKm = (data['service_radius_km'] as num?)?.toDouble() ?? 10;
      } else {
        _radiusSupported = false; // Stage 21 migration not run yet
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _detectLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentPosition(
        context: context,
        reason: 'So clients near you can find you, and travel fees are worked out from your base.',
      );
      if (pos == null) return;
      setState(() {
        _latCtrl.text = pos.latitude.toStringAsFixed(6);
        _lngCtrl.text = pos.longitude.toStringAsFixed(6);
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Location detected!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
                'Could not detect location. Please enter your address manually.'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final userId = supabase.auth.currentUser!.id;
    final payload = {
      'provider_id': userId,
      'bio':         _bioCtrl.text.trim(),
      'title':       _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      'address':     _addressCtrl.text.trim(),
      'latitude':    double.tryParse(_latCtrl.text.trim()),
      'longitude':   double.tryParse(_lngCtrl.text.trim()),
      if (_radiusSupported) 'service_radius_km': _radiusKm,
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
    _bioCtrl.dispose(); _titleCtrl.dispose(); _addressCtrl.dispose();
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
            style: TextStyle(
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
      child: Divider(color: AppColors.border, thickness: 1),
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
              // -- Avatar Section --
              Center(
                child: AvatarWidget(
                  avatarUrl: _avatarUrl,
                  fallbackName: _fullName,
                  size: 100,
                  showEditButton: true,
                  onEdit: () async {
                    final url = await AvatarUploadHelper.pickAndUpload(context);
                    if (url != null && mounted) {
                      setState(() => _avatarUrl = url);
                    }
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Center(
                child: Text(
                  'Tap to change photo',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textTertiary,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // -- Title --
              _buildSectionHeader('What you do', TablerIcons.id_badge_2),
              TextFormField(
                controller: _titleCtrl,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Your title',
                  hintText: 'e.g. Nail tech, Braider, Barber, Lash artist',
                ),
              ),
              const SizedBox(height: AppSpacing.md),

              // -- Bio Section --
              _buildSectionHeader('About You', TablerIcons.user),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.cardLight,
                  borderRadius: AppRadius.lgAll,
                  border: Border.all(color: AppColors.border),
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
                  style: TextStyle(
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
              _buildSectionHeader('Location', TablerIcons.map_pin),
              TextFormField(
                controller: _addressCtrl,
                decoration: const InputDecoration(
                  labelText: 'Service Area / Address',
                  hintText: 'e.g. Borrowdale, Harare',
                  prefixIcon: Icon(TablerIcons.map),
                ),
                validator: (v) =>
                    v == null || v.trim().isEmpty ? 'Please add your address' : null,
              ),
              const SizedBox(height: AppSpacing.lg),

              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _detectLocation,
                  icon: _locating
                      ? SizedBox(
                          height: 16, width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2, color: AppColors.primary,
                          ),
                        )
                      : const Icon(TablerIcons.current_location, size: 18),
                  label: Text(_locating
                      ? 'Detecting...'
                      : _latCtrl.text.isNotEmpty
                          ? 'Location set (${_latCtrl.text}, ${_lngCtrl.text})'
                          : 'Use my current location'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: BorderSide(color: AppColors.primary.withValues(alpha: 0.3)),
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  ),
                ),
              ),
              if (_latCtrl.text.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                    vertical: AppSpacing.sm,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.08),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Row(
                    children: [
                      Icon(TablerIcons.circle_check,
                          size: 14, color: AppColors.success),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Coordinates saved — clients nearby will find you.',
                          style: TextStyle(fontSize: 12, color: AppColors.success),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_radiusSupported) ...[
                _buildSectionDivider(),

                // -- Service Radius --
                _buildSectionHeader('Service Radius', TablerIcons.radar),
                Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.cardLight,
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(color: AppColors.border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'How far will you travel for bookings?',
                              style: TextStyle(
                                  fontSize: 14, color: AppColors.textPrimary),
                            ),
                          ),
                          Text(
                            '${_radiusKm.round()} km',
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary),
                          ),
                        ],
                      ),
                      Slider(
                        value: _radiusKm,
                        min: 2,
                        max: 50,
                        divisions: 48,
                        activeColor: AppColors.primary,
                        onChanged: (v) => setState(() => _radiusKm = v),
                      ),
                      Text(
                        'Clients within this radius will see you in their results.',
                        style: TextStyle(
                            fontSize: 11.5, color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                ),
              ],

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
                      : const Icon(TablerIcons.device_floppy),
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
