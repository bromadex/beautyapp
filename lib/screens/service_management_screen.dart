import 'package:flutter/material.dart';
import '../supabase_client.dart';
import '../theme.dart';

class ServiceManagementScreen extends StatefulWidget {
  const ServiceManagementScreen({super.key});
  @override
  State<ServiceManagementScreen> createState() =>
      _ServiceManagementScreenState();
}

class _ServiceManagementScreenState extends State<ServiceManagementScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  List<Map<String, dynamic>> _services = [];
  List<Map<String, dynamic>> _categories = [];
  List<Map<String, dynamic>> _packages = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
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

    List<Map<String, dynamic>> addons = [];
    try {
      addons = List<Map<String, dynamic>>.from(
        await supabase
            .from('service_addons')
            .select()
            .eq('provider_id', userId)
            .order('sort_order'),
      );
    } catch (_) {}

    List<Map<String, dynamic>> pkgs = [];
    try {
      pkgs = List<Map<String, dynamic>>.from(
        await supabase
            .from('service_packages')
            .select('*, package_services(service_id, services(service_name))')
            .eq('provider_id', userId)
            .order('created_at'),
      );
    } catch (_) {}

    // Attach addons to services
    final svcList = List<Map<String, dynamic>>.from(svcs);
    for (final svc in svcList) {
      svc['addons'] = addons.where((a) => a['service_id'] == svc['id']).toList();
    }

    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(cats);
        _services = svcList;
        _packages = pkgs;
        _loading = false;
      });
    }
  }

  // ── Service CRUD ──

  void _showAddEditDialog({Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['service_name'] ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final durationCtrl = TextEditingController(
        text: existing?['duration_minutes']?.toString() ?? '60');
    String? selectedCategoryId = existing?['category_id'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
          title: Row(children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                existing == null ? Icons.add_rounded : Icons.edit_rounded,
                color: AppColors.primary, size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(existing == null ? 'Add Service' : 'Edit Service'),
          ]),
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
                    child: Text('${c['name']}'),
                  )).toList(),
                  onChanged: (v) => setDialogState(() => selectedCategoryId = v),
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
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty ||
                    priceCtrl.text.trim().isEmpty ||
                    selectedCategoryId == null) return;
                final userId = supabase.auth.currentUser!.id;
                final payload = {
                  'provider_id': userId,
                  'category_id': selectedCategoryId,
                  'service_name': nameCtrl.text.trim(),
                  'price': double.parse(priceCtrl.text.trim()),
                  'duration_minutes': int.tryParse(durationCtrl.text.trim()) ?? 60,
                };
                if (existing == null) {
                  await supabase.from('services').insert(payload);
                } else {
                  await supabase.from('services').update(payload).eq('id', existing['id']);
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

  Future<void> _deleteService(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: const Text('Delete Service?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('services').delete().eq('id', id);
      _load();
    }
  }

  // ── Add-on CRUD ──

  void _showAddonDialog(String serviceId, {Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final durCtrl = TextEditingController(text: existing?['duration_minutes']?.toString() ?? '0');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: Text(existing == null ? 'Add Add-on' : 'Edit Add-on'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Add-on Name',
                  hintText: 'e.g. Hair Wash',
                  prefixIcon: Icon(Icons.add_circle_outline),
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
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: TextField(
                    controller: durCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Extra min',
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              if (nameCtrl.text.trim().isEmpty) return;
              final userId = supabase.auth.currentUser!.id;
              final payload = {
                'service_id': serviceId,
                'provider_id': userId,
                'name': nameCtrl.text.trim(),
                'price': double.tryParse(priceCtrl.text.trim()) ?? 0,
                'duration_minutes': int.tryParse(durCtrl.text.trim()) ?? 0,
              };
              if (existing == null) {
                await supabase.from('service_addons').insert(payload);
              } else {
                await supabase.from('service_addons').update(payload).eq('id', existing['id']);
              }
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteAddon(String id) async {
    await supabase.from('service_addons').delete().eq('id', id);
    _load();
  }

  // ── Package CRUD ──

  void _showPackageDialog({Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final priceCtrl = TextEditingController(text: existing?['package_price']?.toString() ?? '');
    final existingServiceIds = existing != null
        ? (existing['package_services'] as List?)?.map((ps) => ps['service_id'] as String).toSet() ?? <String>{}
        : <String>{};
    Set<String> selectedServiceIds = Set.from(existingServiceIds);

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          double individualTotal = 0;
          for (final svc in _services) {
            if (selectedServiceIds.contains(svc['id'])) {
              individualTotal += (svc['price'] as num?)?.toDouble() ?? 0;
            }
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
            title: Text(existing == null ? 'Create Package' : 'Edit Package'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Package Name',
                        hintText: 'e.g. Bridal Package',
                        prefixIcon: Icon(Icons.inventory_2_outlined),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Description (optional)',
                        hintText: 'What\'s included',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    const Text('Select Services:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: AppSpacing.sm),
                    if (_services.isEmpty)
                      const Text('Add services first', style: TextStyle(color: AppColors.textTertiary))
                    else
                      ...(_services.map((svc) => CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(svc['service_name'], style: const TextStyle(fontSize: 14)),
                        subtitle: Text('\$${svc['price']}', style: const TextStyle(fontSize: 12)),
                        value: selectedServiceIds.contains(svc['id']),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selectedServiceIds.add(svc['id']);
                            } else {
                              selectedServiceIds.remove(svc['id']);
                            }
                          });
                        },
                      ))),
                    if (selectedServiceIds.length >= 2) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'Individual total: \$${individualTotal.toStringAsFixed(0)}',
                        style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: priceCtrl,
                      decoration: InputDecoration(
                        labelText: 'Package Price (\$)',
                        hintText: individualTotal > 0 ? 'Suggested: \$${(individualTotal * 0.85).toStringAsFixed(0)}' : '',
                        prefixIcon: const Icon(Icons.attach_money_rounded),
                      ),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              FilledButton(
                onPressed: () async {
                  if (nameCtrl.text.trim().isEmpty ||
                      priceCtrl.text.trim().isEmpty ||
                      selectedServiceIds.length < 2) return;
                  final userId = supabase.auth.currentUser!.id;
                  final payload = {
                    'provider_id': userId,
                    'name': nameCtrl.text.trim(),
                    'description': descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
                    'package_price': double.parse(priceCtrl.text.trim()),
                  };

                  String packageId;
                  if (existing == null) {
                    final result = await supabase.from('service_packages').insert(payload).select('id').single();
                    packageId = result['id'];
                  } else {
                    packageId = existing['id'];
                    await supabase.from('service_packages').update(payload).eq('id', packageId);
                    await supabase.from('package_services').delete().eq('package_id', packageId);
                  }

                  final rows = selectedServiceIds.map((sid) => ({
                    'package_id': packageId,
                    'service_id': sid,
                  })).toList();
                  await supabase.from('package_services').insert(rows);

                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                },
                child: Text(existing == null ? 'Create' : 'Save'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePackage(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete Package?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await supabase.from('package_services').delete().eq('package_id', id);
      await supabase.from('service_packages').delete().eq('id', id);
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Services'),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: AppColors.primary,
          unselectedLabelColor: AppColors.textTertiary,
          indicatorColor: AppColors.primary,
          tabs: const [
            Tab(text: 'Services'),
            Tab(text: 'Add-ons'),
            Tab(text: 'Packages'),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          switch (_tabCtrl.index) {
            case 0:
              _showAddEditDialog();
              break;
            case 1:
              if (_services.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add a service first')),
                );
                return;
              }
              _showSelectServiceForAddon();
              break;
            case 2:
              if (_services.length < 2) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add at least 2 services to create a package')),
                );
                return;
              }
              _showPackageDialog();
              break;
          }
        },
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Add'),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : TabBarView(
              controller: _tabCtrl,
              children: [
                _buildServicesTab(),
                _buildAddonsTab(),
                _buildPackagesTab(),
              ],
            ),
    );
  }

  void _showSelectServiceForAddon() {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Add add-on to which service?'),
        children: _services.map((svc) => SimpleDialogOption(
          onPressed: () {
            Navigator.pop(ctx);
            _showAddonDialog(svc['id']);
          },
          child: Text(svc['service_name']),
        )).toList(),
      ),
    );
  }

  // ── Services Tab ──

  Widget _buildServicesTab() {
    if (_services.isEmpty) return _buildEmptyState('No services yet', 'Add the services you offer so clients can discover and book you.', Icons.content_cut_rounded);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 80),
      itemCount: _services.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) => _buildServiceCard(_services[i]),
    );
  }

  Widget _buildServiceCard(Map<String, dynamic> s) {
    final catName = (s['service_categories'] as Map?)?['name'] ?? '';
    final isActive = s['is_active'] as bool;
    final addons = s['addons'] as List? ?? [];

    return Container(
      decoration: BoxDecoration(
        color: AppColors.cardLight,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: isActive ? AppColors.border : AppColors.surfaceMuted),
      ),
      child: Column(
        children: [
          Padding(
            padding: AppSpacing.cardPadding,
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: isActive ? AppColors.primary.withValues(alpha: 0.1) : AppColors.surfaceMuted,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(Icons.content_cut_rounded,
                  color: isActive ? AppColors.primary : AppColors.textTertiary, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s['service_name'], style: TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15,
                      color: isActive ? AppColors.textPrimary : AppColors.textTertiary,
                    )),
                    const SizedBox(height: AppSpacing.xs),
                    Row(children: [
                      Container(width: 6, height: 6, decoration: BoxDecoration(
                        color: isActive ? AppColors.success : AppColors.textTertiary,
                        shape: BoxShape.circle,
                      )),
                      const SizedBox(width: AppSpacing.xs),
                      Text(isActive ? 'Active' : 'Inactive', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w500,
                        color: isActive ? AppColors.success : AppColors.textTertiary,
                      )),
                      const SizedBox(width: AppSpacing.sm),
                      Text('$catName  --  ${s['duration_minutes']} min', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), borderRadius: AppRadius.smAll),
                child: Text('\$${s['price']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.primary)),
              ),
              const SizedBox(width: AppSpacing.xs),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert_rounded, color: AppColors.textTertiary),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                itemBuilder: (_) => [
                  PopupMenuItem(onTap: () => _showAddEditDialog(existing: s),
                    child: const Row(children: [Icon(Icons.edit_outlined, size: 20, color: AppColors.textSecondary), SizedBox(width: AppSpacing.md), Text('Edit')])),
                  PopupMenuItem(onTap: () => _showAddonDialog(s['id']),
                    child: const Row(children: [Icon(Icons.add_circle_outline, size: 20, color: AppColors.textSecondary), SizedBox(width: AppSpacing.md), Text('Add Add-on')])),
                  PopupMenuItem(onTap: () => _toggleActive(s),
                    child: Row(children: [Icon(isActive ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20, color: AppColors.textSecondary), const SizedBox(width: AppSpacing.md), Text(isActive ? 'Deactivate' : 'Activate')])),
                  PopupMenuItem(onTap: () => _deleteService(s['id']),
                    child: const Row(children: [Icon(Icons.delete_outline, size: 20, color: AppColors.error), SizedBox(width: AppSpacing.md), Text('Delete', style: TextStyle(color: AppColors.error))])),
                ],
              ),
            ]),
          ),
          if (addons.isNotEmpty) ...[
            Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: Column(
                children: addons.map<Widget>((a) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Icon(Icons.add_circle_outline, size: 14, color: AppColors.textTertiary),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(a['name'], style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                    Text('+\$${a['price']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.primary)),
                    if ((a['duration_minutes'] ?? 0) > 0)
                      Text(' +${a['duration_minutes']}min', style: const TextStyle(fontSize: 11, color: AppColors.textTertiary)),
                    const SizedBox(width: AppSpacing.sm),
                    GestureDetector(
                      onTap: () => _showAddonDialog(s['id'], existing: a),
                      child: const Icon(Icons.edit, size: 14, color: AppColors.textTertiary),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    GestureDetector(
                      onTap: () => _deleteAddon(a['id']),
                      child: const Icon(Icons.close, size: 14, color: AppColors.error),
                    ),
                  ]),
                )).toList(),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Add-ons Tab ──

  Widget _buildAddonsTab() {
    final allAddons = <Map<String, dynamic>>[];
    for (final svc in _services) {
      for (final addon in (svc['addons'] as List? ?? [])) {
        allAddons.add({...addon, '_service_name': svc['service_name'], '_service_id': svc['id']});
      }
    }
    if (allAddons.isEmpty) {
      return _buildEmptyState('No add-ons yet', 'Add optional extras to your services (e.g. Hair Wash +\$5).', Icons.add_circle_outline);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 80),
      itemCount: allAddons.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) {
        final a = allAddons[i];
        return ListTile(
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          tileColor: AppColors.cardLight,
          leading: Container(
            width: 40, height: 40,
            decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.1), borderRadius: AppRadius.smAll),
            child: const Icon(Icons.add_circle_outline, color: AppColors.primary, size: 20),
          ),
          title: Text(a['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
          subtitle: Text('For: ${a['_service_name']}', style: const TextStyle(fontSize: 12)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('+\$${a['price']}', style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
              PopupMenuButton(
                icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textTertiary),
                itemBuilder: (_) => [
                  PopupMenuItem(onTap: () => _showAddonDialog(a['_service_id'], existing: a), child: const Text('Edit')),
                  PopupMenuItem(onTap: () => _deleteAddon(a['id']), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Packages Tab ──

  Widget _buildPackagesTab() {
    if (_packages.isEmpty) {
      return _buildEmptyState('No packages yet', 'Bundle services together at a discounted price (e.g. Bridal Package).', Icons.inventory_2_outlined);
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 80),
      itemCount: _packages.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
      itemBuilder: (_, i) {
        final pkg = _packages[i];
        final services = (pkg['package_services'] as List?)
            ?.map((ps) => ps['services']?['service_name'] ?? '')
            .where((n) => n.isNotEmpty)
            .toList() ?? [];
        return Container(
          decoration: BoxDecoration(
            color: AppColors.cardLight,
            borderRadius: AppRadius.lgAll,
            border: Border.all(color: AppColors.border),
          ),
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: AppRadius.mdAll),
                  child: const Icon(Icons.inventory_2_outlined, color: AppColors.secondary, size: 22),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pkg['name'], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                    if (pkg['description'] != null)
                      Text(pkg['description'], style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                  ],
                )),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: AppColors.secondary.withValues(alpha: 0.1), borderRadius: AppRadius.smAll),
                  child: Text('\$${pkg['package_price']}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: AppColors.secondary)),
                ),
                PopupMenuButton(
                  icon: const Icon(Icons.more_vert, color: AppColors.textTertiary),
                  itemBuilder: (_) => [
                    PopupMenuItem(onTap: () => _showPackageDialog(existing: pkg), child: const Text('Edit')),
                    PopupMenuItem(onTap: () => _deletePackage(pkg['id']), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                  ],
                ),
              ]),
              if (services.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.md),
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  children: services.map((s) => Chip(
                    label: Text(s, style: const TextStyle(fontSize: 12)),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                  )).toList(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(String title, String subtitle, IconData icon) {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.xxl),
              decoration: BoxDecoration(color: AppColors.primary.withValues(alpha: 0.08), shape: BoxShape.circle),
              child: Icon(icon, size: 48, color: AppColors.primary),
            ),
            const SizedBox(height: AppSpacing.xxl),
            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const SizedBox(height: AppSpacing.sm),
            Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.5)),
          ],
        ),
      ),
    );
  }
}
