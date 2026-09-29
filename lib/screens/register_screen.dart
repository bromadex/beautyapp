import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/referral_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class RegisterScreen extends StatefulWidget {
  /// Referral code from an invite link (/register?ref=CODE).
  final String? refCode;
  const RegisterScreen({super.key, this.refCode});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _locationCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  String _userType = 'client';
  bool _loading = false;
  bool _googleLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;

  List<Map<String, dynamic>> _categories = [];
  final Set<String> _selectedCategories = {};

  @override
  void initState() {
    super.initState();
    if ((widget.refCode ?? '').isNotEmpty) {
      _refCtrl.text = widget.refCode!.toUpperCase();
      _userType = 'provider';
    }
    _loadCategories();
  }

  Future<void> _loadCategories() async {
    try {
      final data = await supabase
          .from('service_categories')
          .select()
          .order('sort_order');
      if (mounted) {
        setState(() {
          _categories = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (_) {}
  }

  Future<void> _signUpWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('pending_user_type', _userType);
        await supabase.auth.signInWithOAuth(
          OAuthProvider.google,
          redirectTo: Uri.base.origin,
        );
      } else {
        const webClientId =
            '549119684234-bpgdfj7880f9g7gsba897hg8790im54o.apps.googleusercontent.com';

        final googleUser = await GoogleSignIn(
          serverClientId: webClientId,
        ).signIn();

        if (googleUser == null) {
          if (mounted) setState(() => _googleLoading = false);
          return;
        }

        final googleAuth = await googleUser.authentication;
        final idToken = googleAuth.idToken;
        final accessToken = googleAuth.accessToken;

        if (idToken == null) throw Exception('No ID token from Google');

        await supabase.auth.signInWithIdToken(
          provider: OAuthProvider.google,
          idToken: idToken,
          accessToken: accessToken,
        );

        if (mounted) {
          final user = supabase.auth.currentUser;
          if (user != null) {
            final existing = await supabase
                .from('profiles')
                .select('id')
                .eq('id', user.id)
                .maybeSingle();

            if (existing == null) {
              await supabase.from('profiles').upsert({
                'id': user.id,
                'full_name':
                    user.userMetadata?['full_name'] ??
                    user.userMetadata?['name'] ??
                    '',
                'user_type': _userType,
              }, onConflict: 'id');
              if (_userType == 'provider') {
                await supabase.from('provider_profiles').upsert({
                  'provider_id': user.id,
                  'bio': '',
                }, onConflict: 'provider_id');
              }
            } else {
              await supabase
                  .from('profiles')
                  .update({'user_type': _userType})
                  .eq('id', user.id);
              if (_userType == 'provider') {
                await supabase.from('provider_profiles').upsert({
                  'provider_id': user.id,
                  'bio': '',
                }, onConflict: 'provider_id');
              }
            }
            await supabase.auth.updateUser(
              UserAttributes(data: {'user_type': _userType}),
            );
          }
          context.go(_userType == 'provider' ? '/provider/home' : '/home');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Google sign-in is not configured yet.'),
            backgroundColor: AppColors.warning,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;

    if (_userType == 'provider' && _selectedCategories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select at least one specialty'),
          backgroundColor: AppColors.warning,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
        ),
      );
      return;
    }

    setState(() => _loading = true);

    try {
      final res = await supabase.auth.signUp(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
        data: {
          'user_type': _userType,
          'full_name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'location': _locationCtrl.text.trim(),
        },
      );

      final userId = res.user?.id;
      if (userId != null) {
        await supabase.from('profiles').upsert({
          'id': userId,
          'full_name': _nameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'location': _locationCtrl.text.trim(),
          'user_type': _userType,
        }, onConflict: 'id');

        if (_userType == 'provider') {
          await supabase.from('provider_profiles').upsert({
            'provider_id': userId,
            'bio': '',
            'address': _locationCtrl.text.trim(),
          }, onConflict: 'provider_id');
        }
      }

      if (_userType == 'provider' && _refCtrl.text.trim().isNotEmpty) {
        await applyReferralCode(_refCtrl.text.trim(), context: context);
      }

      if (mounted) context.go('/home');
    } on AuthException catch (e) {
      if (mounted) {
        String msg = e.message;
        if (e.statusCode == '422' ||
            msg.contains('already registered') ||
            msg.contains('already been registered') ||
            msg.contains('already exists')) {
          msg = 'This email is already registered. Try signing in instead.';
        } else if (msg.contains('valid email')) {
          msg = 'Please enter a valid email address.';
        } else if (msg.contains('least 6')) {
          msg = 'Password must be at least 6 characters.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(msg),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registration error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _refCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _locationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    MediaQuery.of(context).padding.top + 8,
                    24,
                    0,
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => context.go('/login'),
                        icon: const Icon(TablerIcons.arrow_left),
                        tooltip: 'Back to sign in',
                      ),
                      const Spacer(),
                      const BrandMark(size: 32),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Create your account',
                        style: Theme.of(context).textTheme.headlineLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _userType == 'provider'
                            ? 'Grow your beauty business — clients book you directly.'
                            : 'Book trusted beauty pros near you.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // --- Form section ---
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 500),
                  curve: Curves.easeOut,
                  builder: (context, value, child) {
                    return Opacity(
                      opacity: value,
                      child: Transform.translate(
                        offset: Offset(0, 20 * (1 - value)),
                        child: child,
                      ),
                    );
                  },
                  child: Padding(
                    padding: AppSpacing.screenPadding,
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: AppSpacing.xxl),

                          // --- Role picker ---
                          _buildSectionLabel('I am a...'),
                          const SizedBox(height: AppSpacing.md),
                          Row(
                            children: [
                              Expanded(
                                child: _RoleCard(
                                  icon: TablerIcons.user,
                                  label: 'Client',
                                  subtitle: 'Book services',
                                  selected: _userType == 'client',
                                  onTap: () =>
                                      setState(() => _userType = 'client'),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _RoleCard(
                                  icon: TablerIcons.sparkles,
                                  label: 'Provider',
                                  subtitle: 'Offer services',
                                  selected: _userType == 'provider',
                                  onTap: () =>
                                      setState(() => _userType = 'provider'),
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: AppSpacing.xl),

                          // --- Google Sign-Up ---
                          OutlinedButton.icon(
                            onPressed: _googleLoading
                                ? null
                                : _signUpWithGoogle,
                            icon: _googleLoading
                                ? SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.textSecondary,
                                    ),
                                  )
                                : Image.network(
                                    'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                                    width: 20,
                                    height: 20,
                                    errorBuilder: (_, __, ___) => const Icon(
                                      TablerIcons.brand_google,
                                      size: 24,
                                    ),
                                  ),
                            label: Text(
                              _googleLoading
                                  ? 'Signing up...'
                                  : 'Sign up with Google',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.textPrimary,
                              side: BorderSide(color: AppColors.borderStrong),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.mdAll,
                              ),
                            ),
                          ),

                          const SizedBox(height: AppSpacing.xl),

                          Row(
                            children: [
                              Expanded(
                                child: Divider(color: AppColors.borderStrong),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.lg,
                                ),
                                child: Text(
                                  'or register with email',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.textTertiary,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Divider(color: AppColors.borderStrong),
                              ),
                            ],
                          ),

                          // --- Provider specialties ---
                          if (_userType == 'provider' &&
                              _categories.isNotEmpty) ...[
                            const SizedBox(height: AppSpacing.xxl),
                            _buildSectionLabel('Your specialties'),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'Select the services you offer',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textTertiary,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Wrap(
                              spacing: AppSpacing.sm,
                              runSpacing: AppSpacing.sm,
                              children: _categories.map((cat) {
                                final id = cat['id'] as String;
                                final selected = _selectedCategories.contains(
                                  id,
                                );
                                return FilterChip(
                                  label: Text(
                                    '${cat['name']}',
                                  ),
                                  selected: selected,
                                  onSelected: (_) {
                                    setState(() {
                                      if (selected) {
                                        _selectedCategories.remove(id);
                                      } else {
                                        _selectedCategories.add(id);
                                      }
                                    });
                                  },
                                  selectedColor: AppColors.primary.withValues(
                                    alpha: 0.12,
                                  ),
                                  checkmarkColor: AppColors.primary,
                                  labelStyle: TextStyle(
                                    color: selected
                                        ? AppColors.primary
                                        : AppColors.textPrimary,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadius.mdAll,
                                    side: BorderSide(
                                      color: selected
                                          ? AppColors.primary.withValues(
                                              alpha: 0.3,
                                            )
                                          : AppColors.borderStrong,
                                    ),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.sm,
                                    vertical: AppSpacing.xs,
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.xxl),

                          // --- Personal info ---
                          _buildSectionLabel('Personal information'),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _nameCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Full Name',
                              prefixIcon: Icon(TablerIcons.user),
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter your full name'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          TextFormField(
                            controller: _phoneCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Phone Number',
                              hintText: '077XXXXXXX',
                              prefixIcon: Icon(TablerIcons.phone),
                            ),
                            keyboardType: TextInputType.phone,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter your phone number'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          TextFormField(
                            controller: _locationCtrl,
                            decoration: InputDecoration(
                              labelText: 'Location',
                              hintText: _userType == 'provider'
                                  ? 'e.g. Borrowdale, Harare'
                                  : 'e.g. Harare, Zimbabwe',
                              prefixIcon: const Icon(
                                TablerIcons.map_pin,
                              ),
                            ),
                            textCapitalization: TextCapitalization.words,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.trim().isEmpty
                                ? 'Enter your location'
                                : null,
                          ),

                          const SizedBox(height: AppSpacing.xxl),

                          // --- Account credentials ---
                          _buildSectionLabel('Account credentials'),
                          const SizedBox(height: AppSpacing.md),
                          TextFormField(
                            controller: _emailCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(TablerIcons.mail),
                            ),
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || !v.contains('@')
                                ? 'Enter a valid email'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          TextFormField(
                            controller: _passwordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon: const Icon(TablerIcons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? TablerIcons.eye_off
                                      : TablerIcons.eye,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            validator: (v) => v == null || v.length < 6
                                ? 'Min 6 characters'
                                : null,
                          ),
                          const SizedBox(height: AppSpacing.lg),

                          TextFormField(
                            controller: _confirmPasswordCtrl,
                            decoration: InputDecoration(
                              labelText: 'Confirm Password',
                              prefixIcon: const Icon(TablerIcons.lock),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirm
                                      ? TablerIcons.eye_off
                                      : TablerIcons.eye,
                                  size: 20,
                                ),
                                onPressed: () => setState(
                                  () => _obscureConfirm = !_obscureConfirm,
                                ),
                              ),
                            ),
                            obscureText: _obscureConfirm,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _register(),
                            validator: (v) {
                              if (v == null || v.isEmpty)
                                return 'Confirm your password';
                              if (v != _passwordCtrl.text)
                                return 'Passwords do not match';
                              return null;
                            },
                          ),
                          if (_userType == 'provider') ...[
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _refCtrl,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Referral code (optional)',
                                hintText: 'From the pro who invited you',
                                prefixIcon: Icon(TablerIcons.ticket),
                              ),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.xxxl),

                          // --- Submit ---
                          FilledButton(
                            onPressed: _loading ? null : _register,
                            child: _loading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    _userType == 'provider'
                                        ? 'Create beauty pro account'
                                        : 'Create account',
                                  ),
                          ),

                          if (_userType == 'provider') ...[
                            const SizedBox(height: AppSpacing.lg),
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.md),
                              decoration: BoxDecoration(
                                color: AppColors.success.withValues(
                                  alpha: 0.08,
                                ),
                                borderRadius: AppRadius.mdAll,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    TablerIcons.circle_check,
                                    size: 16,
                                    color: AppColors.success,
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Expanded(
                                    child: Text(
                                      'Free to create — only \$3 when you start accepting bookings',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.success,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          const SizedBox(height: AppSpacing.xl),
                          Center(
                            child: TextButton(
                              onPressed: () => context.go('/login'),
                              child: Text.rich(
                                TextSpan(
                                  text: 'Already have an account? ',
                                  style: TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w400,
                                  ),
                                  children: [
                                    TextSpan(
                                      text: 'Sign in',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _RoleCard({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.lgAll,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(
          vertical: AppSpacing.lg,
          horizontal: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary.withValues(alpha: 0.06)
              : Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderStrong,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : AppColors.surfaceMuted,
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                color: selected ? AppColors.primary : AppColors.textTertiary,
                size: 24,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: selected ? AppColors.primary : AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.7)
                    : AppColors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
