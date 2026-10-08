import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/referral_service.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/legal.dart';
import '../widgets/role_card.dart';
import '../widgets/ui.dart';

/// Shown once after a first Google or Apple sign-in, which skips the sign-up
/// form: account type (unless picked on the sign-up page), phone number, and
/// a referral code for pros.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _loading = true;
  bool _saving = false;
  bool _askType = true;
  String _type = 'client';
  String _name = '';
  final _phoneCtrl = TextEditingController();
  final _refCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _phoneCtrl.dispose();
    _refCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final p = await supabase
          .from('profiles')
          .select('user_type, full_name, phone')
          .eq('id', supabase.auth.currentUser!.id)
          .maybeSingle();
      if (!mounted) return;
      setState(() {
        _type = (p?['user_type'] ?? 'client') as String;
        _name = ((p?['full_name'] ?? '') as String).split(' ').first;
        _phoneCtrl.text = p?['phone'] ?? '';
        // Chosen on the sign-up page already? Then don't ask again.
        _askType = prefs.getBool('signup_choice_made') != true;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(String m, {bool error = false}) => ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(m), backgroundColor: error ? AppColors.error : null));

  Future<void> _finish() async {
    final phone = _phoneCtrl.text.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.length < 9) {
      _toast('Add your phone number, e.g. 0771 234 567', error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('profiles').update({
        'user_type': _type,
        'phone': phone,
        'needs_onboarding': false,
      }).eq('id', uid);

      // The database only allows the type to change on a brand-new account.
      final row = await supabase.from('profiles').select('user_type').eq('id', uid).single();
      final type = row['user_type'] as String;
      if (type == 'provider') {
        await supabase.from('provider_profiles').upsert(
          {'provider_id': uid, 'bio': ''},
          onConflict: 'provider_id',
          ignoreDuplicates: true,
        );
      }
      await supabase.auth.updateUser(UserAttributes(data: {'user_type': type}));
      if (type == 'provider' && _refCtrl.text.trim().isNotEmpty && mounted) {
        await applyReferralCode(_refCtrl.text.trim(), context: context);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('signup_choice_made');
      if (!mounted) return;
      if (type != _type) _toast('This account was already set up, so it stays as it is.');
      // New pros go straight to saying where they work; clients go home.
      context.go(type == 'provider' ? '/provider/home' : '/home');
      if (type == 'provider') context.push('/provider/location');
    } on PostgrestException catch (e) {
      _toast(e.message, error: true);
    } catch (_) {
      _toast('Could not save. Check your connection and try again.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pro = _type == 'provider';
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('Welcome to BeauTap')),
      body: _loading
          ? const LoadingPlaceholder(kind: PlaceholderKind.detail)
          : ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 24), children: [
              Text(_name.isEmpty ? 'Just a few details' : 'Hi $_name, just a few details',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('You signed in with Google or Apple, so we need these to finish your account.',
                  style: TextStyle(color: AppColors.textSecondary, height: 1.4)),
              const SizedBox(height: 20),
              if (_askType) ...[
                const Text('What will you use BeauTap for?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 10),
                RoleChoice(value: _type, onChanged: (v) => setState(() => _type = v)),
                const SizedBox(height: 22),
              ],
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Phone number',
                  hintText: '0771 234 567',
                  prefixIcon: const Icon(TablerIcons.phone),
                  helperMaxLines: 2,
                  helperText: pro
                      ? 'Clients use it to reach you on WhatsApp about bookings.'
                      : 'Your pro uses it to reach you about your booking.',
                ),
              ),
              if (pro) ...[
                const SizedBox(height: 14),
                TextField(
                  controller: _refCtrl,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(
                    labelText: 'Referral code (optional)',
                    hintText: 'From the pro who invited you',
                    prefixIcon: Icon(TablerIcons.gift),
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.mdAll),
                  child: Text(
                    'Next you\'ll set where you work, then add your services and prices. '
                    'Clients can find you once your location is set.',
                    style: TextStyle(color: AppColors.textPrimary, height: 1.4, fontSize: 13.5),
                  ),
                ),
              ],
            ]),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const PrivacyNotice(lead: 'By continuing you agree to our '),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _saving ? null : _finish,
                      child: Text(_saving ? 'Saving…' : 'Continue'),
                    ),
                  ),
                ]),
              ),
            ),
    );
  }
}
