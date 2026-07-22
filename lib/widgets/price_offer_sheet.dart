import 'package:flutter/material.dart';
import '../theme.dart';

class PriceOfferSheet extends StatefulWidget {
  final double listedPrice;
  final String serviceName;
  final String providerName;

  const PriceOfferSheet({
    super.key,
    required this.listedPrice,
    required this.serviceName,
    required this.providerName,
  });

  @override
  State<PriceOfferSheet> createState() => _PriceOfferSheetState();
}

class _PriceOfferSheetState extends State<PriceOfferSheet> {
  late double _offeredPrice;
  late TextEditingController _priceCtrl;

  @override
  void initState() {
    super.initState();
    _offeredPrice = widget.listedPrice;
    _priceCtrl = TextEditingController(text: _offeredPrice.toStringAsFixed(0));
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    super.dispose();
  }

  void _adjustPrice(double delta) {
    setState(() {
      _offeredPrice = (_offeredPrice + delta).clamp(1, widget.listedPrice * 2);
      _priceCtrl.text = _offeredPrice.toStringAsFixed(0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final savings = widget.listedPrice - _offeredPrice;
    final isDiscount = savings > 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: AppSpacing.xxl,
        right: AppSpacing.xxl,
        top: AppSpacing.lg,
        bottom: MediaQuery.of(context).viewInsets.bottom + AppSpacing.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text(
            'Offer Your Price',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '${widget.serviceName} by ${widget.providerName}',
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.xxl),

          // Listed price reference
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: AppRadius.mdAll,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Listed price',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 14)),
                Text(
                  '\$${widget.listedPrice.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),

          // Price input with +/- buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _PriceButton(
                icon: Icons.remove_rounded,
                onTap: () => _adjustPrice(-1),
                onLongPress: () => _adjustPrice(-5),
              ),
              const SizedBox(width: AppSpacing.xl),
              SizedBox(
                width: 120,
                child: TextField(
                  controller: _priceCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: AppColors.primary,
                  ),
                  decoration: const InputDecoration(
                    prefixText: '\$ ',
                    prefixStyle: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    border: InputBorder.none,
                  ),
                  onChanged: (v) {
                    final parsed = double.tryParse(v);
                    if (parsed != null && parsed > 0) {
                      setState(() => _offeredPrice = parsed);
                    }
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.xl),
              _PriceButton(
                icon: Icons.add_rounded,
                onTap: () => _adjustPrice(1),
                onLongPress: () => _adjustPrice(5),
              ),
            ],
          ),

          if (isDiscount) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.1),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                'You save \$${savings.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.success,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xxl),

          // Send offer button
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context, _offeredPrice),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              ),
              child: Text(
                'Send Offer — \$${_offeredPrice.toStringAsFixed(0)}',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),

          // Book at listed price
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () =>
                  Navigator.pop(context, widget.listedPrice),
              child: Text(
                'Book at listed price (\$${widget.listedPrice.toStringAsFixed(0)})',
                style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 14),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          Text(
            'The provider can accept, counter-offer, or decline. Offers expire in 24 hours.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _PriceButton({
    required this.icon,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: onLongPress,
      child: Material(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
        ),
      ),
    );
  }
}
