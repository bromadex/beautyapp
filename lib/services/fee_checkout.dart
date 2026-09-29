import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';

import '../supabase_client.dart';
import '../theme.dart';
import 'paynow_service.dart';
import '../widgets/ui.dart';

/// What BeauTap charges pros. Keep in step with public._fee_price().
class BeauTapFee {
  final String purpose; // subscription | featured | product_pack | product_boost
  final String? plan; // activation | monthly | salon; 'large' for the 50-listing pack
  final String? productId; // product_boost only
  const BeauTapFee(this.purpose, [this.plan, this.productId]);

  double get amount => switch ((purpose, plan)) {
        ('subscription', 'activation') => 3,
        ('subscription', 'monthly') => 5,
        ('subscription', 'salon') => 15,
        ('featured', _) => 3,
        ('product_pack', 'large') => 10,
        ('product_pack', _) => 5,
        ('product_boost', _) => 1,
        _ => 0,
      };

  String get label => switch ((purpose, plan)) {
        ('subscription', 'salon') => 'Salon plan (1 month)',
        ('subscription', 'activation') => 'Pro plan activation (first month)',
        ('subscription', _) => 'Pro plan (1 month)',
        ('featured', _) => 'Featured for 7 days',
        ('product_pack', 'large') => '50 product listings for 30 days',
        ('product_pack', _) => '20 product listings for 30 days',
        ('product_boost', _) => 'Boost one product for 7 days',
        _ => 'BeauTap',
      };
}

enum FeeOutcome { paid, sentManually, cancelled }

/// Lets the pro pay BeauTap by Paynow, or, as a backup, send EcoCash to
/// BeauTap's number themselves and wait for an admin to confirm it.
class FeeCheckout {
  static Future<FeeOutcome> run(BuildContext context, BeauTapFee fee) async {
    String? manualNumber;
    try {
      final row = await supabase
          .from('app_settings')
          .select('value')
          .eq('key', 'beautap_ecocash_number')
          .maybeSingle();
      manualNumber = (row?['value'] ?? '').toString().trim();
      if (manualNumber.isEmpty) manualNumber = null;
    } catch (_) {}
    if (!context.mounted) return FeeOutcome.cancelled;

    final choice = await showModalBottomSheet<String>(
      useRootNavigator: true,
      isScrollControlled: true,
      context: context,
      showDragHandle: true,
      builder: (ctx) => SheetScroll(child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Pay \$${fee.amount.toStringAsFixed(0)}', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(fee.label, style: TextStyle(color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            _Option(
              icon: TablerIcons.bolt,
              title: 'Pay now',
              subtitle: 'Online through Paynow (Zimswitch, InnBucks and more). Active straight away.',
              onTap: () => Navigator.pop(ctx, 'paynow'),
            ),
            if (manualNumber != null) ...[
              const SizedBox(height: 8),
              _Option(
                icon: TablerIcons.device_mobile,
                title: 'Send EcoCash yourself',
                subtitle: 'If Paynow isn\'t working. Active once we check it, usually within a few hours.',
                onTap: () => Navigator.pop(ctx, 'manual'),
              ),
            ],
          ]),
        ),
      )),
    );
    if (choice == null || !context.mounted) return FeeOutcome.cancelled;

    if (choice == 'manual') {
      final sent = await context.push<bool>('/pay-beautap?purpose=${fee.purpose}'
          '${fee.plan != null ? '&plan=${fee.plan}' : ''}${fee.productId != null ? '&product=${fee.productId}' : ''}');
      return sent == true ? FeeOutcome.sentManually : FeeOutcome.cancelled;
    }

    final outcome = await PaynowCheckout.run(
      context,
      purpose: fee.purpose,
      tier: fee.plan,
      months: fee.purpose == 'subscription' ? 1 : null,
      productId: fee.productId,
    );
    if (outcome == PaynowOutcome.paid) return FeeOutcome.paid;
    if (context.mounted && (outcome == PaynowOutcome.failed || outcome == PaynowOutcome.timeout)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(manualNumber != null
            ? 'Paynow didn\'t go through. You can try again, or choose "Send EcoCash yourself".'
            : 'Payment was not completed. Please try again.'),
        backgroundColor: AppColors.warning,
      ));
    }
    return FeeOutcome.cancelled;
  }
}

class _Option extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  const _Option({required this.icon, required this.title, required this.subtitle, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(borderRadius: AppRadius.mdAll, border: Border.all(color: AppColors.border)),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: AppColors.primarySoft, borderRadius: AppRadius.smAll),
              child: Icon(icon, color: AppColors.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              ]),
            ),
            Icon(TablerIcons.chevron_right, color: AppColors.textTertiary),
          ]),
        ),
      );
}
