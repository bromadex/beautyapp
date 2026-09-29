import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/avatar_widget.dart';

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
  String? _gender; // woman | man | null (not said)
  final _addressCtrl = TextEditingController();
  final _latCtrl     = TextEditingController();
  final _lngCtrl     = TextEditingController();
  double _radiusKm = 10;
  bool _radiusSupported = true;
  bool _loading = false;
  bool _saving  = false;
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
          .select('*, cities(name)')
          .eq('provider_id', uid)
          .single();
      _bioCtrl.text     = data['bio']     ?? '';
      _titleCtrl.text   = data['title']   ?? '';
      _gender           = data['gender'];
      _addressCtrl.text = [data['area'], (data['cities'] as Map?)?['name']].where((x) => (x ?? '').toString().isNotEmpty).join(', ');
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

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    final userId = supabase.auth.currentUser!.id;
    final payload = {
      'provider_id': userId,
      'bio':         _bioCtrl.text.trim(),
      'title':       _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      'gender':      _gender,
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
              const SizedBox(height: AppSpacing.sm),
              Text('You are', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 'woman', label: Text('A woman')),
                    ButtonSegment(value: 'man', label: Text('A man')),
                    ButtonSegment(value: 'none', label: Text('Don\'t show')),
                  ],
                  selected: {_gender ?? 'none'},
                  onSelectionChanged: (v) => setState(() => _gender = v.first == 'none' ? null : v.first),
                ),
              ),
              const SizedBox(height: 4),
              Text('Some clients, for example for massage, prefer a woman or a man. They can filter by this.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
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
              _buildSectionHeader('Where you work', TablerIcons.map_pin),
              Material(
                color: AppColors.card,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll, side: BorderSide(color: AppColors.border)),
                child: ListTile(
                  leading: Icon(TablerIcons.map_pin, color: AppColors.primary),
                  title: Text(_addressCtrl.text.isEmpty ? 'Set your city and area' : _addressCtrl.text),
                  subtitle: const Text('Clients find and book you by this. Change it if you move.'),
                  trailing: const Icon(TablerIcons.chevron_right),
                  onTap: () async {
                    await context.push('/provider/location');
                    _load();
                  },
                ),
              ),
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
