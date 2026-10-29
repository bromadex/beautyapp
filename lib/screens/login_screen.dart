import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/account_guard.dart';
import '../services/social_auth.dart';
import '../widgets/apple_sign_in_button.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../utils/feel.dart';
import '../widgets/ui.dart';
import '../services/guest_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _googleLoading = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    // Suspended while the app was open, or Google/Apple refused a banned account.
    final err = '${Uri.base.queryParameters['error_description'] ?? ''}${Uri.base.fragment}'.toLowerCase();
    if (err.contains('banned')) AccountGuard.justSuspended = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AccountGuard.showIfSuspended(context);
    });
  }

  /// Signs in with email and password. Returns a message to show, or null on success.
  Future<String?> _login() async {
    if (!_formKey.currentState!.validate()) return '';
    try {
      await supabase.auth.signInWithPassword(
        email: _emailCtrl.text.trim(),
        password: _passwordCtrl.text,
      );
      return null;
    } on AuthException catch (e) {
      final msg = e.message;
      if (msg.contains('Invalid login credentials')) return 'Wrong email or password. Please try again.';
      if (msg.toLowerCase().contains('banned')) return AccountGuard.message;
      if (msg.contains('Email not confirmed')) return 'Please check your email to confirm your account.';
      return msg;
    } catch (_) {
      return 'Could not sign in. Check your connection and try again.';
    }
  }

  /// The email form, in a sheet over the photos.
  void _openEmailSheet() {
    String? error;
    bool busy = false;
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      builder: (sheetCtx) => SheetScroll(
        child: StatefulBuilder(
          builder: (sheetCtx, setSheet) => Padding(
            padding: EdgeInsets.fromLTRB(24, 8, 24, 24 + MediaQuery.of(sheetCtx).viewInsets.bottom),
            child: Form(
              key: _formKey,
              child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('Sign in with email', style: Theme.of(sheetCtx).textTheme.headlineSmall),
                const SizedBox(height: 6),
                Text('Welcome back. Book trusted beauty pros near you.',
                    style: TextStyle(fontSize: 15, color: AppColors.textSecondary)),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailCtrl,
                  decoration: const InputDecoration(labelText: 'Email address', prefixIcon: Icon(TablerIcons.mail)),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.next,
                  autofocus: true,
                  validator: (v) => v == null || !v.contains('@') ? 'Enter a valid email' : null,
                ),
                const SizedBox(height: 14),
                StatefulBuilder(
                  builder: (_, setField) => TextFormField(
                    controller: _passwordCtrl,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      prefixIcon: const Icon(TablerIcons.lock),
                      suffixIcon: IconButton(
                        tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                        icon: Icon(_obscurePassword ? TablerIcons.eye_off : TablerIcons.eye, size: 20),
                        onPressed: () => setField(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    autofillHints: const [AutofillHints.password],
                    textInputAction: TextInputAction.done,
                    validator: (v) => v == null || v.isEmpty ? 'Enter your password' : null,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(onPressed: _forgotPassword, child: const Text('Forgot password?')),
                ),
                if (error != null && error!.isNotEmpty) ...[
                  Text(error!, style: TextStyle(color: AppColors.errorText, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 12),
                ],
                FilledButton(
                  onPressed: busy
                      ? null
                      : () async {
                          setSheet(() {
                            busy = true;
                            error = null;
                          });
                          final msg = await _login();
                          if (!sheetCtx.mounted) return;
                          if (msg == null) {
                            Haptics.firm();
                            Navigator.pop(sheetCtx);
                            if (mounted) context.go('/home');
                          } else {
                            if (msg.isNotEmpty) Haptics.warn();
                            setSheet(() {
                              busy = false;
                              error = msg;
                            });
                          }
                        },
                  child: busy
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2, valueColor: AlwaysStoppedAnimation(AppColors.onPrimary)),
                        )
                      : const Text('Sign in'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    Navigator.pop(sheetCtx);
                    context.go('/register');
                  },
                  child: const Text('New to BeauTap? Create an account'),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      await SocialAuth.start();
    } on AuthException catch (e) {
      _googleError(e.message);
    } catch (_) {
      _googleError('Could not open Google sign-in. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  void _googleError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }

  void _forgotPassword() {
    final resetEmailCtrl = TextEditingController(text: _emailCtrl.text.trim());
    showModalBottomSheet(
      useRootNavigator: true,
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        bool sending = false;
        bool sent = false;
        return SheetScroll(child: StatefulBuilder(
          builder: (ctx, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: AppSpacing.xxl,
              right: AppSpacing.xxl,
              top: AppSpacing.xxl,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + AppSpacing.xxl,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.borderStrong,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Icon(
                        sent
                            ? TablerIcons.mail_check
                            : TablerIcons.lock_cog,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      sent ? 'Check your email' : 'Reset Password',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (sent) ...[
                  Text(
                    'We sent a password reset link to ${resetEmailCtrl.text.trim()}. Check your inbox and follow the link.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Got it'),
                  ),
                ] else ...[
                  Text(
                    'Enter your email and we\'ll send you a link to reset your password.',
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextField(
                    controller: resetEmailCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(TablerIcons.mail),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    autofocus: true,
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  FilledButton(
                    onPressed: sending
                        ? null
                        : () async {
                            final email = resetEmailCtrl.text.trim();
                            if (email.isEmpty || !email.contains('@')) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                SnackBar(
                                  content: const Text('Enter a valid email'),
                                  backgroundColor: AppColors.warning,
                                  behavior: SnackBarBehavior.floating,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: AppRadius.mdAll,
                                  ),
                                ),
                              );
                              return;
                            }
                            setSheetState(() => sending = true);
                            try {
                              await supabase.auth.resetPasswordForEmail(email);
                              setSheetState(() {
                                sending = false;
                                sent = true;
                              });
                            } catch (e) {
                              setSheetState(() => sending = false);
                              if (ctx.mounted) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('Error: $e'),
                                    backgroundColor: AppColors.error,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: AppRadius.mdAll,
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: sending
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : const Text('Send Reset Link'),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ));
      },
    );
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    _pages.dispose();
    super.dispose();
  }

  final _pages = PageController();
  int _page = 0;

  static const _slides = [
    (photo: 'assets/photos/welcome_1.jpg', lead: 'Braiders, barbers & nail techs ', gold: 'near you',
     body: 'Find trusted beauty pros wherever you are in Zimbabwe.'),
    (photo: 'assets/photos/welcome_2.jpg', lead: 'Book in seconds, ', gold: 'pay with EcoCash',
     body: 'Pick a time, pay a small deposit, and you are booked.'),
    (photo: 'assets/photos/welcome_3.jpg', lead: 'Verified pros, ', gold: 'real reviews',
     body: 'Look for the verified tick and read what clients say before you book.'),
  ];

  Widget _slide(({String photo, String lead, String gold, String body}) s, {required bool wide}) {
    return Stack(fit: StackFit.expand, children: [
      Image.asset(s.photo, fit: BoxFit.cover, alignment: const Alignment(0, -0.5)),
      // Photo fades into the dark panel underneath, so the text stays readable.
      const DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0x1A000000), Color(0x00000000), Color(0x990B0A09), Color(0xFF0B0A09)],
            stops: [0, 0.35, 0.72, 1],
          ),
        ),
      ),
      Positioned(
        left: wide ? 48 : 24,
        right: wide ? 48 : 24,
        bottom: wide ? 64 : 8, // room for the page dots underneath on laptops
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text.rich(
            TextSpan(children: [
              TextSpan(text: s.lead),
              TextSpan(text: s.gold, style: const TextStyle(color: AppColors.gold)),
            ]),
            style: TextStyle(
              fontFamily: 'InterDisplay',
              fontSize: wide ? 48 : 34,
              height: 1.07,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),
          Text(s.body, style: const TextStyle(fontSize: 15.5, height: 1.45, color: Color(0xFFD9D1C4))),
        ]),
      ),
    ]);
  }

  Widget _photos({required bool wide}) {
    return Stack(children: [
      PageView(
        controller: _pages,
        onPageChanged: (i) {
          Haptics.light();
          setState(() => _page = i);
        },
        children: [for (final s in _slides) _slide(s, wide: wide)],
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(10)),
                child: const Text('b',
                    style: TextStyle(fontFamily: 'InterDisplay', fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF17130E))),
              ),
              const SizedBox(width: 10),
              const Text('BeauTap', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
      ),
    ]);
  }

  Widget _dots() => Row(children: [
        for (var i = 0; i < _slides.length; i++)
          AnimatedContainer(
            duration: Motion.of(context),
            curve: Motion.curve,
            margin: const EdgeInsets.only(right: 6),
            width: i == _page ? 26 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == _page ? AppColors.gold : const Color(0x55FFFFFF),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ]);

  /// Sign-in buttons. [onPhoto]: white-on-dark styling under the photos.
  Widget _buttons({required bool onPhoto}) {
    final faint = onPhoto ? const Color(0xFFD9D1C4) : AppColors.textSecondary;
    final strong = onPhoto ? Colors.white : AppColors.textPrimary;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      FilledButton.icon(
        onPressed: _googleLoading ? null : _signInWithGoogle,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF17130E),
          minimumSize: const Size.fromHeight(54),
          side: onPhoto ? null : BorderSide(color: AppColors.border),
        ),
        icon: _googleLoading
            ? const SizedBox(height: 18, width: 18, child: CircularProgressIndicator.adaptive(strokeWidth: 2))
            : Image.network(
                'https://www.gstatic.com/firebasejs/ui/2.0.0/images/auth/google.svg',
                width: 20,
                height: 20,
                errorBuilder: (_, _, _) => const Icon(TablerIcons.brand_google, size: 22),
              ),
        label: Text(_googleLoading ? 'Signing in…' : 'Continue with Google'),
      ),
      AppleSignInButton(label: 'Continue with Apple', onPhoto: onPhoto),
      const SizedBox(height: 10),
      FilledButton(
        onPressed: _openEmailSheet,
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.gold,
          foregroundColor: const Color(0xFF17130E),
          minimumSize: const Size.fromHeight(54),
        ),
        child: const Text('Continue with email'),
      ),
      const SizedBox(height: 6),
      TextButton(
        onPressed: () async {
          if (await GuestService.continueAsGuest(context) && mounted) context.go('/home');
        },
        style: TextButton.styleFrom(foregroundColor: strong),
        child: const Text('Just browsing? Continue as guest'),
      ),
      Wrap(alignment: WrapAlignment.center, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Are you a beauty pro?', style: TextStyle(fontSize: 14, color: faint)),
        TextButton(
          onPressed: () => context.go('/register?as=pro'),
          style: TextButton.styleFrom(foregroundColor: onPhoto ? AppColors.gold : AppColors.goldText),
          child: const Text('Join as a pro'),
        ),
      ]),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (isWideLayout(context)) {
      // Laptops: photos on the left, sign-in on a cream panel on the right.
      return Scaffold(
        body: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Stack(children: [
              _photos(wide: true),
              Positioned(left: 48, bottom: 32, child: _dots()),
            ]),
          ),
          SizedBox(
            width: 480,
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text('Welcome to BeauTap', style: Theme.of(context).textTheme.headlineLarge),
                    const SizedBox(height: 8),
                    Text('Sign in to book trusted beauty pros near you.',
                        style: TextStyle(fontSize: 16, color: AppColors.textSecondary)),
                    const SizedBox(height: 28),
                    _buttons(onPhoto: false),
                  ]),
                ),
              ),
            ),
          ),
        ]),
      );
    }
    // Phones: swipeable photos, buttons on the dark panel they fade into.
    return Scaffold(
      backgroundColor: const Color(0xFF0B0A09),
      body: Column(children: [
        Expanded(child: _photos(wide: false)),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _dots(),
              const SizedBox(height: 18),
              _buttons(onPhoto: true),
            ]),
          ),
        ),
      ]),
    );
  }
}
