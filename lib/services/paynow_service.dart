import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../supabase_client.dart';
import '../theme.dart';

/// Stage 20: Paynow checkout client.
///
/// Talks to the `initiate-payment` / `check-payment-status` edge functions.
/// When Paynow isn't configured yet (no merchant credentials, or functions
/// not deployed), [PaynowCheckout.run] returns [PaynowOutcome.unconfigured]
/// and callers fall back to the simulated payment path.
class PaynowInitResult {
  final bool configured;
  final String? paymentId;
  final String? browserUrl;
  final String? instructions;
  final String? error;

  const PaynowInitResult({
    required this.configured,
    this.paymentId,
    this.browserUrl,
    this.instructions,
    this.error,
  });
}

enum PaynowOutcome { paid, failed, cancelled, timeout, unconfigured }

class PaynowService {
  /// Starts a Paynow transaction server-side.
  static Future<PaynowInitResult> initiate({
    required String purpose,
    String? bookingId,
    String method = 'web',
    String? phone,
    String? tier,
    int? months,
  }) async {
    try {
      final res = await supabase.functions.invoke('initiate-payment', body: {
        'purpose': purpose,
        if (bookingId != null) 'bookingId': bookingId,
        'method': method,
        if (phone != null) 'phone': phone,
        if (tier != null) 'tier': tier,
        if (months != null) 'months': months,
      });

      final data = res.data as Map<String, dynamic>? ?? {};
      if (data['configured'] == false) {
        return const PaynowInitResult(configured: false);
      }
      if (data['error'] != null) {
        return PaynowInitResult(
            configured: true, error: data['error'].toString());
      }
      return PaynowInitResult(
        configured: true,
        paymentId: data['paymentId'] as String?,
        browserUrl: data['browserUrl'] as String?,
        instructions: data['instructions'] as String?,
      );
    } catch (_) {
      // Function not deployed / network error → simulated fallback
      return const PaynowInitResult(configured: false);
    }
  }

  /// Returns 'paid' | 'failed' | 'pending'.
  static Future<String> checkStatus(String paymentId) async {
    try {
      final res = await supabase.functions.invoke('check-payment-status',
          body: {'paymentId': paymentId});
      final data = res.data as Map<String, dynamic>? ?? {};
      return (data['status'] as String?) ?? 'pending';
    } catch (_) {
      return 'pending';
    }
  }
}

/// Drives the full checkout UX: initiate → open Paynow / USSD push →
/// poll until final status, with a progress dialog the user can cancel.
class PaynowCheckout {
  static Future<PaynowOutcome> run(
    BuildContext context, {
    required String purpose,
    String? bookingId,
    String method = 'web', // web | ecocash | onemoney | telecash
    String? phone,
    String? tier,
    int? months,
  }) async {
    final init = await PaynowService.initiate(
      purpose: purpose,
      bookingId: bookingId,
      method: method,
      phone: phone,
      tier: tier,
      months: months,
    );

    if (!init.configured) return PaynowOutcome.unconfigured;

    if (init.error != null || init.paymentId == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment could not be started: ${init.error ?? 'unknown error'}'),
            backgroundColor: AppColors.error,
          ),
        );
      }
      return PaynowOutcome.failed;
    }

    // Card / web flow → open the Paynow payment page
    if (method == 'web' && init.browserUrl != null) {
      await launchUrl(Uri.parse(init.browserUrl!),
          mode: LaunchMode.externalApplication);
    }

    if (!context.mounted) return PaynowOutcome.cancelled;

    // Poll every 4s for up to 4 minutes while showing progress
    final outcome = await showDialog<PaynowOutcome>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _PaymentWaitDialog(
        paymentId: init.paymentId!,
        isMobileMoney: method != 'web',
        instructions: init.instructions,
      ),
    );

    return outcome ?? PaynowOutcome.cancelled;
  }
}

class _PaymentWaitDialog extends StatefulWidget {
  final String paymentId;
  final bool isMobileMoney;
  final String? instructions;

  const _PaymentWaitDialog({
    required this.paymentId,
    required this.isMobileMoney,
    this.instructions,
  });

  @override
  State<_PaymentWaitDialog> createState() => _PaymentWaitDialogState();
}

class _PaymentWaitDialogState extends State<_PaymentWaitDialog> {
  Timer? _timer;
  int _elapsed = 0;
  static const _pollInterval = 4;
  static const _timeoutSeconds = 240;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: _pollInterval), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    _elapsed += _pollInterval;
    final status = await PaynowService.checkStatus(widget.paymentId);
    if (!mounted) return;
    if (status == 'paid') {
      Navigator.pop(context, PaynowOutcome.paid);
    } else if (status == 'failed') {
      Navigator.pop(context, PaynowOutcome.failed);
    } else if (_elapsed >= _timeoutSeconds) {
      Navigator.pop(context, PaynowOutcome.timeout);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.md),
          const CircularProgressIndicator(color: AppColors.primary),
          const SizedBox(height: AppSpacing.xl),
          Text(
            widget.isMobileMoney
                ? 'Approve on Your Phone'
                : 'Complete Payment in Browser',
            style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            widget.instructions ??
                (widget.isMobileMoney
                    ? 'Enter your mobile money PIN when the prompt appears on your phone.'
                    : 'Finish the payment on the Paynow page, then return here.'),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary, height: 1.4),
          ),
          if (widget.isMobileMoney) ...[
            const SizedBox(height: AppSpacing.md),
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.08),
                borderRadius: AppRadius.smAll,
              ),
              child: const Text(
                'No prompt? Make sure the SIM for your mobile money account is in this phone and has network signal — WiFi alone is not enough for the USSD prompt.',
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary, height: 1.4),
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, PaynowOutcome.cancelled),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}
