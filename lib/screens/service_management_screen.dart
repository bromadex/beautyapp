import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
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

    List<Map<String, dynamic>> tiers = [];
    try {
      tiers = List<Map<String, dynamic>>.from(
        await supabase
            .from('service_tiers')
            .select()
            .eq('provider_id', userId)
            .order('sort_order', ascending: true)
            .order('price', ascending: true),
      );
    } catch (_) {}

    // Attach addons to services
    final svcList = List<Map<String, dynamic>>.from(svcs);
    for (final svc in svcList) {
      svc['addons'] = addons.where((a) => a['service_id'] == svc['id']).toList();
      svc['tiers'] = tiers.where((t) => t['service_id'] == svc['id']).toList();
    }

    if (mounted) {
      setState(() {
        _categories = List<Map<String, dynamic>>.from(cats);
        _services = svcList;
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
    final descCtrl = TextEditingController(text: existing?['description'] ?? '');
    final includesCtrl = TextEditingController(text: existing?['includes'] ?? '');
    final aftercareCtrl = TextEditingController(text: existing?['aftercare'] ?? '');
    String? selectedCategoryId = existing?['category_id'];
    String? imageUrl = existing?['image_url'];
    Uint8List? newImage;
    bool saving = false;

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
                InkWell(
                  borderRadius: AppRadius.mdAll,
                  onTap: () async {
                    final picked = await ImagePicker()
                        .pickImage(source: ImageSource.gallery, imageQuality: 80, maxWidth: 1400);
                    if (picked == null) return;
                    final bytes = await picked.readAsBytes();
                    setDialogState(() => newImage = bytes);
                  },
                  child: Container(
                    height: 130,
                    width: double.infinity,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: AppRadius.mdAll,
                      border: Border.all(color: AppColors.border),
                    ),
                    child: newImage != null
                        ? Image.memory(newImage!, fit: BoxFit.cover)
                        : imageUrl != null
                            ? Image.network(imageUrl, fit: BoxFit.cover)
                            : const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.add_photo_alternate_outlined, color: AppColors.textTertiary),
                                SizedBox(height: 4),
                                Text('Add a photo of this service',
                                    style: TextStyle(fontSize: 13, color: AppColors.textTertiary)),
                              ]),
                  ),
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
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: descCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                    hintText: 'What the client gets, hair length, style…',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: includesCtrl,
                  maxLines: 4,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'What\'s included (one per line)',
                    hintText: 'Wash\nBlow-dry\nHair provided',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: aftercareCtrl,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Aftercare tips (optional)',
                    hintText: 'e.g. Sleep with a satin scarf, avoid washing for 3 days',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: saving ? null : () async {
                final price = double.tryParse(priceCtrl.text.trim());
                if (nameCtrl.text.trim().isEmpty || price == null || selectedCategoryId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Pick a category and enter a name and price')));
                  return;
                }
                String? opt(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
                final userId = supabase.auth.currentUser!.id;
                final payload = {
                  'provider_id': userId,
                  'category_id': selectedCategoryId,
                  'service_name': nameCtrl.text.trim(),
                  'price': price,
                  'duration_minutes': int.tryParse(durationCtrl.text.trim()) ?? 60,
                  'description': opt(descCtrl),
                  'includes': opt(includesCtrl),
                  'aftercare': opt(aftercareCtrl),
                };
                setDialogState(() => saving = true);
                try {
                  final String id;
                  if (existing == null) {
                    final row = await supabase.from('services').insert(payload).select('id').single();
                    id = row['id'];
                  } else {
                    id = existing['id'];
                    await supabase.from('services').update(payload).eq('id', id);
                  }
                  if (newImage != null) {
                    final path = '$userId/$id-${DateTime.now().millisecondsSinceEpoch}.jpg';
                    await supabase.storage.from('service-images').uploadBinary(path, newImage!,
                        fileOptions: const FileOptions(contentType: 'image/jpeg', upsert: true));
                    await supabase.from('services').update({
                      'image_url': supabase.storage.from('service-images').getPublicUrl(path),
                    }).eq('id', id);
                  }
                  if (ctx.mounted) Navigator.pop(ctx);
                  _load();
                } catch (e) {
                  setDialogState(() => saving = false);
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.error));
                  }
                }
              },
              child: Text(saving ? 'Saving…' : existing == null ? 'Add' : 'Save'),
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

  void _showTierDialog(String serviceId, {Map<String, dynamic>? existing}) {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final priceCtrl = TextEditingController(text: existing?['price']?.toString() ?? '');
    final durCtrl = TextEditingController(text: (existing?['duration_minutes'] ?? 60).toString());
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add an option' : 'Edit option'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('e.g. Regular, Premium, Bridal — each with its own price and time.',
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          TextField(
            controller: nameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Option name', hintText: 'Premium'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Price', prefixText: '\$ '),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: durCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Minutes'),
              ),
            ),
          ]),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () async {
              final price = double.tryParse(priceCtrl.text.trim());
              final dur = int.tryParse(durCtrl.text.trim());
              if (nameCtrl.text.trim().isEmpty || price == null || price <= 0 || dur == null || dur <= 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Enter a name, price and minutes')));
                return;
              }
              final payload = {
                'service_id': serviceId,
                'provider_id': supabase.auth.currentUser!.id,
                'name': nameCtrl.text.trim(),
                'price': price,
                'duration_minutes': dur,
              };
              try {
                if (existing == null) {
                  await supabase.from('service_tiers').insert(payload);
                } else {
                  await supabase.from('service_tiers').update(payload).eq('id', existing['id']);
                }
                if (ctx.mounted) Navigator.pop(ctx);
                _load();
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.error));
                }
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTier(String id) async {
    await supabase.from('service_tiers').delete().eq('id', id);
    _load();
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
            Tab(text: 'Options'),
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
              if (_services.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add a service first')),
                );
                return;
              }
              _pickService('Add an option to which service?', (id) => _showTierDialog(id));
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
                _buildTiersTab(),
              ],
            ),
    );
  }

  void _pickService(String title, void Function(String id) onPick) {
    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: _services
            .map((svc) => SimpleDialogOption(
                  onPressed: () {
                    Navigator.pop(ctx);
                    onPick(svc['id']);
                  },
                  child: Text(svc['service_name']),
                ))
            .toList(),
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

  // ── Options (tiers) Tab ──

  Widget _buildTiersTab() {
    final withTiers = _services.where((s) => (s['tiers'] as List? ?? []).isNotEmpty).toList();
    if (withTiers.isEmpty) {
      return _buildEmptyState('No options yet',
          'Offer levels of the same service — e.g. Knotless braids: Regular \$25, Premium \$40, Bridal \$60.',
          Icons.layers_outlined);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, 80),
      children: [
        for (final svc in withTiers) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 8),
            child: Row(children: [
              Expanded(child: Text(svc['service_name'] ?? '', style: Theme.of(context).textTheme.titleMedium)),
              TextButton.icon(
                onPressed: () => _showTierDialog(svc['id']),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add'),
              ),
            ]),
          ),
          for (final t in (svc['tiers'] as List).cast<Map<String, dynamic>>())
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  title: Text(t['name'] ?? ''),
                  subtitle: Text('${t['duration_minutes']} min'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('\$${t['price']}',
                        style: const TextStyle(fontWeight: FontWeight.w800, color: AppColors.primary)),
                    PopupMenuButton(
                      icon: const Icon(Icons.more_vert, size: 20, color: AppColors.textTertiary),
                      itemBuilder: (_) => [
                        PopupMenuItem(onTap: () => _showTierDialog(svc['id'], existing: t), child: const Text('Edit')),
                        PopupMenuItem(
                            onTap: () => _deleteTier(t['id']),
                            child: const Text('Delete', style: TextStyle(color: AppColors.error))),
                      ],
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ],
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
