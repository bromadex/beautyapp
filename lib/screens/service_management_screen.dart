import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});
  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen> {
  List<Map<String, dynamic>> _services    = [];
  List<Map<String, dynamic>> _categories  = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;

    final cats = await supabase
        .from('service_categories').select().order('sort_order');
    final svcs = await supabase
        .from('services')
        .select('*, service_categories(name)')
        .eq('provider_id', userId)
        .order('created_at');

    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(cats);
        _services   = List<Map<String, dynamic>>.from(svcs);
        _loading    = false;
      });
    }
  }

  void _showAddEditDialog({Map<String, dynamic>? existing}) {
    final nameCtrl     = TextEditingController(text: existing?['service_name'] ?? '');
    final priceCtrl    = TextEditingController(text: existing?['price']?.toString() ?? '');
    final durationCtrl = TextEditingController(
        text: existing?['duration_minutes']?.toString() ?? '60');
    String? selectedCategoryId = existing?['category_id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(
                  existing == null ? Icons.add_rounded : Icons.edit_rounded,
                  color: AppColors.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(existing == null ? 'Add Service' : 'Edit Service'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  borderRadius: AppRadius.mdAll,
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text('${c['icon'] ?? ''} ${c['name']}'),
                  )).toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedCategoryId = v),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Service Name',
                    hintText: 'e.g. Box Braids -- Medium',
                    prefixIcon: Icon(Icons.content_cut_rounded),
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Price (\$)',
                        prefixIcon: Icon(Icons.attach_money_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: TextField(
                      controller: durationCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Duration (min)',
                        prefixIcon: Icon(Icons.timer_outlined),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    priceCtrl.text.trim().isEmpty ||
                    selectedCategoryId == null) {
                  return;
                }
                final userId = supabase.auth.currentUser!.id;
                final payload = {
                  'provider_id':      userId,
                  'category_id':      selectedCategoryId,
                  'service_name':     nameCtrl.text.trim(),
                  'price':            double.parse(priceCtrl.text.trim()),
                  'duration_minutes': int.tryParse(durationCtrl.text.trim()) ?? 60,
                };
                if (existing == null) {
                  await supabase.from('services').insert(payload);
                } else {
                  await supabase.from('services')
                      .update(payload).eq('id', existing['id']);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              },
              child: Text(existing == null ? 'Add' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleActive(Map<String, dynamic> service) async {
    await supabase.from('services')
        .update({'is_active': !(service['is_active'] as bool)})
        .eq('id', service['id']);
    _load();
  }

  Future<void> _delete(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: const Text('Delete Service?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: AppColors.error),
              child: const Text('Delete')),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('services').delete().eq('id', id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My Services')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add Service'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _services.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 80,
                  ),
                  itemCount: _services.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _buildServiceCard(_services[i]),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.content_cut_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            const Text(
              'No services yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Add the services you offer so clients\ncan discover and book you.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Add Your First Service'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.lg,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> s) {
    final catName =
        (s['service_categories'] as Map?)?['name'] ?? '';
    final isActive = s['is_active'] as bool;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: isActive
              ? Colors.grey.shade200
              : Colors.grey.shade100,
        ),
      ),
      child: Padding(
        padding: AppSpacing.cardPadding,
        child: Row(
          children: [
            // Service icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isActive
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : Colors.grey.shade100,
                borderRadius: AppRadius.mdAll,
              ),
              child: Icon(
                Icons.content_cut_rounded,
                color: isActive ? AppColors.primary : AppColors.textTertiary,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),

            // Service details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s['service_name'],
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                      color: isActive
                          ? AppColors.textPrimary
                          : AppColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isActive
                              ? AppColors.success
                              : AppColors.textTertiary,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        isActive ? 'Active' : 'Inactive',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: isActive
                              ? AppColors.success
                              : AppColors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Text(
                        '$catName  --  ${s['duration_minutes']} min',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Price
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: AppRadius.smAll,
              ),
              child: Text(
                '\$${s['price']}',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.xs),

            // Menu
            PopupMenuButton(
              icon: const Icon(Icons.more_vert_rounded,
                  color: AppColors.textTertiary),
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
              itemBuilder: (_) => [
                PopupMenuItem(
                  onTap: () => _showAddEditDialog(existing: s),
                  child: const Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 20,
                          color: AppColors.textSecondary),
                      SizedBox(width: AppSpacing.md),
                      Text('Edit'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  onTap: () => _toggleActive(s),
                  child: Row(
                    children: [
                      Icon(
                        isActive
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Text(isActive ? 'Deactivate' : 'Activate'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  onTap: () => _delete(s['id']),
                  child: const Row(
                    children: [
                      Icon(Icons.delete_outline, size: 20,
                          color: AppColors.error),
                      SizedBox(width: AppSpacing.md),
                      Text('Delete',
                          style: TextStyle(color: AppColors.error)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
