import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../supabase_client.dart';
import '../theme.dart';

class PromotionManagementScreen extends StatefulWidget {
  const PromotionManagementScreen({super.key});
  @override
  State<PromotionManagementScreen> createState() =>
      _PromotionManagementScreenState();
}

class _PromotionManagementScreenState extends State<PromotionManagementScreen> {
  List<Map<String, dynamic>> _promotions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;
    final data = await supabase
        .from('promotions')
        .select()
        .eq('provider_id', userId)
        .order('created_at', ascending: false);
    if (mounted) {
      setState(() {
        _promotions = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  void _showAddEditDialog({Map<String, dynamic>? existing}) {
    final codeCtrl = TextEditingController(text: existing?['code'] ?? '');
    final descCtrl =
        TextEditingController(text: existing?['description'] ?? '');
    final valueCtrl = TextEditingController(
        text: existing?['discount_value']?.toString() ?? '');
    final minOrderCtrl = TextEditingController(
        text: existing?['min_order_amount']?.toString() ?? '0');
    final maxUsesCtrl = TextEditingController(
        text: existing?['max_uses']?.toString() ?? '');
    String discountType = existing?['discount_type'] ?? 'percentage';
    DateTime? validUntil = existing?['valid_until'] != null
        ? DateTime.tryParse(existing!['valid_until'])
        : null;

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  existing == null
                      ? Icons.add_circle_outline
                      : Icons.edit_outlined,
                  color: AppColors.secondary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(existing == null ? 'New Promotion' : 'Edit Promotion'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeCtrl,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Promo Code *',
                    hintText: 'e.g. SUMMER20',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: descCtrl,
                  decoration: InputDecoration(
                    labelText: 'Description',
                    hintText: 'e.g. Summer sale - 20% off',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.description_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                DropdownButtonFormField<String>(
                  value: discountType,
                  decoration: InputDecoration(
                    labelText: 'Discount Type',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.discount_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'percentage', child: Text('Percentage (%)')),
                    DropdownMenuItem(
                        value: 'fixed', child: Text('Fixed Amount (\$)')),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => discountType = v ?? 'percentage'),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: valueCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Discount Value *',
                    hintText: discountType == 'percentage' ? 'e.g. 20' : 'e.g. 10',
                    suffixText: discountType == 'percentage' ? '%' : '\$',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.local_offer_outlined),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: minOrderCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Min Order Amount',
                    hintText: '0 for no minimum',
                    prefixText: '\$ ',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.attach_money_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: maxUsesCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: 'Max Uses (optional)',
                    hintText: 'Leave blank for unlimited',
                    border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                    prefixIcon: const Icon(Icons.people_outline),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                InkWell(
                  onTap: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate:
                          validUntil ?? DateTime.now().add(const Duration(days: 30)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (date != null) setDialogState(() => validUntil = date);
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'Valid Until (optional)',
                      border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                      prefixIcon: const Icon(Icons.event_outlined),
                      suffixIcon: validUntil != null
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () =>
                                  setDialogState(() => validUntil = null),
                            )
                          : null,
                    ),
                    child: Text(
                      validUntil != null
                          ? '${validUntil!.day}/${validUntil!.month}/${validUntil!.year}'
                          : 'No expiry date',
                      style: TextStyle(
                        color: validUntil != null
                            ? AppColors.textPrimary
                            : AppColors.textTertiary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Cancel',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            FilledButton.icon(
              onPressed: () async {
                final code = codeCtrl.text.trim().toUpperCase();
                final value = double.tryParse(valueCtrl.text.trim());
                if (code.isEmpty || value == null || value <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Please fill in code and discount value'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }
                if (discountType == 'percentage' && value > 100) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Percentage cannot exceed 100%'),
                      backgroundColor: AppColors.error,
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                final userId = supabase.auth.currentUser!.id;
                final record = {
                  'provider_id': userId,
                  'code': code,
                  'description': descCtrl.text.trim().isEmpty
                      ? null
                      : descCtrl.text.trim(),
                  'discount_type': discountType,
                  'discount_value': value,
                  'min_order_amount':
                      double.tryParse(minOrderCtrl.text.trim()) ?? 0,
                  'max_uses': int.tryParse(maxUsesCtrl.text.trim()),
                  'valid_until': validUntil?.toIso8601String(),
                };

                try {
                  if (existing == null) {
                    await supabase.from('promotions').insert(record);
                  } else {
                    await supabase
                        .from('promotions')
                        .update(record)
                        .eq('id', existing['id']);
                  }
                  _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error: $e'),
                        backgroundColor: AppColors.error,
                      ),
                    );
                  }
                }
              },
              icon: Icon(existing == null ? Icons.add : Icons.save, size: 18),
              label: Text(existing == null ? 'Create' : 'Save'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> promo) async {
    final newActive = !(promo['is_active'] as bool? ?? true);
    await supabase
        .from('promotions')
        .update({'is_active': newActive}).eq('id', promo['id']);
    _load();
  }

  Future<void> _delete(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: const Text('Delete Promotion?'),
        content:
            const Text('This will permanently remove this promo code.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await supabase.from('promotions').delete().eq('id', id);
      _load();
    }
  }

  void _shareCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Code "$code" copied to clipboard!'),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Promotions'),
        actions: [
          if (!_loading && _promotions.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.secondary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  '${_promotions.where((p) => p['is_active'] == true).length} active',
                  style: const TextStyle(
                    color: AppColors.secondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('New Promo'),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : _promotions.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: AppSpacing.screenPadding,
                    itemCount: _promotions.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) => _buildPromoCard(_promotions[i]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.secondary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.local_offer_outlined,
                size: 56, color: AppColors.secondary),
          ),
          const SizedBox(height: AppSpacing.xl),
          const Text('No Promotions Yet',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          const Text('Create promo codes to attract more clients.',
              style:
                  TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xxl),
          FilledButton.icon(
            onPressed: () => _showAddEditDialog(),
            icon: const Icon(Icons.add),
            label: const Text('Create Promotion'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoCard(Map<String, dynamic> promo) {
    final isActive = promo['is_active'] as bool? ?? true;
    final code = promo['code'] ?? '';
    final desc = promo['description'] ?? '';
    final type = promo['discount_type'] ?? 'percentage';
    final value = (promo['discount_value'] as num?)?.toDouble() ?? 0;
    final usedCount = promo['used_count'] ?? 0;
    final maxUses = promo['max_uses'];
    final validUntil = promo['valid_until'] != null
        ? DateTime.tryParse(promo['valid_until'])
        : null;
    final isExpired =
        validUntil != null && validUntil.isBefore(DateTime.now());
    final isMaxedOut = maxUses != null && usedCount >= maxUses;

    String discountText = type == 'percentage'
        ? '${value.toStringAsFixed(0)}% OFF'
        : '\$${value.toStringAsFixed(0)} OFF';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: !isActive || isExpired || isMaxedOut
              ? Colors.grey.shade200
              : AppColors.secondary.withValues(alpha: 0.3),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // Colored top strip
          Container(
            height: 3,
            color: !isActive || isExpired || isMaxedOut
                ? Colors.grey.shade300
                : AppColors.secondary,
          ),
          Padding(
            padding: AppSpacing.cardPadding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Code badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: AppSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: isActive && !isExpired && !isMaxedOut
                            ? AppColors.secondary.withValues(alpha: 0.1)
                            : Colors.grey.shade100,
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.confirmation_number_outlined,
                            size: 16,
                            color: isActive && !isExpired && !isMaxedOut
                                ? AppColors.secondary
                                : AppColors.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            code,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                              letterSpacing: 1.2,
                              color: isActive && !isExpired && !isMaxedOut
                                  ? AppColors.secondary
                                  : AppColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    // Discount value
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: AppRadius.smAll,
                      ),
                      child: Text(
                        discountText,
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                if (desc.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(desc,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                ],
                const SizedBox(height: AppSpacing.md),
                // Stats row
                Row(
                  children: [
                    _PromoStat(
                      icon: Icons.people_outline,
                      text: maxUses != null
                          ? '$usedCount / $maxUses used'
                          : '$usedCount used',
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    if (validUntil != null)
                      _PromoStat(
                        icon: Icons.schedule_rounded,
                        text: isExpired
                            ? 'Expired'
                            : 'Until ${validUntil.day}/${validUntil.month}/${validUntil.year}',
                        color: isExpired ? AppColors.error : null,
                      ),
                    if (promo['min_order_amount'] != null &&
                        (promo['min_order_amount'] as num) > 0)
                      _PromoStat(
                        icon: Icons.attach_money_rounded,
                        text:
                            'Min \$${(promo['min_order_amount'] as num).toStringAsFixed(0)}',
                      ),
                  ],
                ),
                if (isExpired || isMaxedOut) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.error.withValues(alpha: 0.1),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      isExpired ? 'Expired' : 'Max uses reached',
                      style: const TextStyle(
                          color: AppColors.error,
                          fontSize: 11,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          // Action buttons
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => _shareCode(code),
                  icon: const Icon(Icons.copy_rounded, size: 20),
                  tooltip: 'Copy Code',
                  color: AppColors.info,
                ),
                IconButton(
                  onPressed: () => _showAddEditDialog(existing: promo),
                  icon: const Icon(Icons.edit_outlined, size: 20),
                  tooltip: 'Edit',
                  color: AppColors.textSecondary,
                ),
                IconButton(
                  onPressed: () => _toggleActive(promo),
                  icon: Icon(
                    isActive
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 20,
                  ),
                  tooltip: isActive ? 'Deactivate' : 'Activate',
                  color: isActive ? AppColors.warning : AppColors.success,
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _delete(promo['id']),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  tooltip: 'Delete',
                  color: AppColors.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PromoStat extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;
  const _PromoStat({required this.icon, required this.text, this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color ?? AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(text,
            style: TextStyle(
                fontSize: 12,
                color: color ?? AppColors.textTertiary)),
      ],
    );
  }
}
