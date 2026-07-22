import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/paynow_service.dart';
import '../supabase_client.dart';
import '../theme.dart';

/// Stage 19: One-time $1 client activation wall.
/// Shown after verification approval, before unlimited booking access.
/// Payment is simulated until Paynow goes live (Stage 20).
class ActivationScreen extends StatefulWidget {
  const ActivationScreen({super.key});

  @override
  State<ActivationScreen> createState() => _ActivationScreenState();
}

class _ActivationScreenState extends State<ActivationScreen> {
  bool _paying = false;

  Future<void> _activate() async {
    setState(() => _paying = true);
    try {
      // Stage 20: real Paynow checkout when configured
      final outcome =
          await PaynowCheckout.run(context, purpose: 'activation');

      if (outcome == PaynowOutcome.paid) {
        // Webhook already set is_activated = true
      } else if (outcome != PaynowOutcome.unconfigured) {
        if (mounted) {
          setState(() => _paying = false);
          if (outcome == PaynowOutcome.failed ||
              outcome == PaynowOutcome.timeout) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(outcome == PaynowOutcome.failed
                    ? 'Payment was not completed. Please try again.'
                    : 'Payment still pending — try reopening this page shortly.'),
                backgroundColor: AppColors.warning,
              ),
            );
          }
        }
        return;
      } else {
        // Simulated payment fallback (Paynow not configured yet)
        await Future.delayed(const Duration(seconds: 2));

        await supabase
            .from('profiles')
            .update({'is_activated': true})
            .eq('id', supabase.auth.currentUser!.id);
      }

      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.check_rounded, color: AppColors.success, size: 40),
                ),
                const SizedBox(height: AppSpacing.xl),
                const Text('Account Activated!', style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                )),
                const SizedBox(height: AppSpacing.sm),
                const Text(
                  'You now have unlimited bookings. Find your perfect stylist!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                ),
                const SizedBox(height: AppSpacing.xl),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      context.go('/browse');
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                    ),
                    child: const Text('Start Browsing'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _paying = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Activation failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Activate Your Account'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/home'),
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
            padding: AppSpacing.screenPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Hero
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xxl),
                  decoration: BoxDecoration(
                    gradient: AppColors.heroGradient,
                    borderRadius: AppRadius.lgAll,
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_open_rounded, color: Colors.white, size: 32),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      const Text(
                        'Unlock Unlimited Bookings',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'One-time activation — not a subscription. Pay once, book forever.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Price card
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text('\$', style: TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.primary,
                            )),
                          ),
                          const Text('1', style: TextStyle(
                            fontSize: 52, fontWeight: FontWeight.w800, color: AppColors.primary, height: 1,
                          )),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('ONE-TIME · NEVER AGAIN', style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w700, color: AppColors.success, letterSpacing: 0.8,
                        )),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Benefits
                _benefit(Icons.all_inclusive_rounded, 'Unlimited bookings', 'Book any stylist, any service, as often as you like'),
                _benefit(Icons.verified_user_outlined, 'A community of real clients', 'Activation keeps fake accounts out, protecting you and your stylists'),
                _benefit(Icons.chat_bubble_outline_rounded, 'Direct messaging', 'Chat with your stylist before and after every booking'),
                _benefit(Icons.location_on_outlined, 'Live tracking', 'See your stylist on the way to your door'),
                const SizedBox(height: AppSpacing.xl),

                // Pay button
                FilledButton(
                  onPressed: _paying ? null : _activate,
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                  ),
                  child: _paying
                      ? const SizedBox(
                          width: 22, height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : const Text('Pay \$1 & Activate', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: AppSpacing.md),
                const Text(
                  'Payments via EcoCash & card coming soon. Activation is currently instant.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _benefit(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 42, height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                Text(subtitle, style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
