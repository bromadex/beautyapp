import 'package:flutter/material.dart';
import '../supabase_client.dart';

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
          title: Text(existing == null ? 'Add Service' : 'Edit Service'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedCategoryId,
                  decoration: const InputDecoration(
                      labelText: 'Category', border: OutlineInputBorder()),
                  items: _categories.map((c) => DropdownMenuItem(
                    value: c['id'] as String,
                    child: Text('${c['icon'] ?? ''} ${c['name']}'),
                  )).toList(),
                  onChanged: (v) =>
                      setDialogState(() => selectedCategoryId = v),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Service Name',
                      hintText: 'e.g. Box Braids – Medium',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: priceCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Price (\$)',
                          border: OutlineInputBorder()),
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: durationCtrl,
                      decoration: const InputDecoration(
                          labelText: 'Duration (min)',
                          border: OutlineInputBorder()),
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
        title: const Text('Delete Service?'),
        content: const Text('This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
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
        icon: const Icon(Icons.add),
        label: const Text('Add Service'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _services.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.content_cut_rounded,
                          size: 64, color: Colors.grey),
                      const SizedBox(height: 16),
                      const Text('No services yet'),
                      const SizedBox(height: 8),
                      FilledButton(
                          onPressed: () => _showAddEditDialog(),
                          child: const Text('Add Your First Service')),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
                  itemCount: _services.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) {
                    final s = _services[i];
                    final catName =
                        (s['service_categories'] as Map?)
                            ?['name'] ?? '';
                    final isActive = s['is_active'] as bool;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: isActive
                              ? Colors.purple.shade100
                              : Colors.grey.shade200,
                          child: Icon(Icons.content_cut_rounded,
                              color: isActive
                                  ? Colors.purple
                                  : Colors.grey,
                              size: 20),
                        ),
                        title: Text(s['service_name'],
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: isActive ? null : Colors.grey)),
                        subtitle: Text(
                            '$catName · ${s['duration_minutes']} min'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('\$${s['price']}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15)),
                            const SizedBox(width: 8),
                            PopupMenuButton(
                              itemBuilder: (_) => [
                                PopupMenuItem(
                                  onTap: () => _showAddEditDialog(existing: s),
                                  child: const ListTile(
                                      leading: Icon(Icons.edit_outlined),
                                      title: Text('Edit'),
                                      contentPadding: EdgeInsets.zero),
                                ),
                                PopupMenuItem(
                                  onTap: () => _toggleActive(s),
                                  child: ListTile(
                                      leading: Icon(isActive
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined),
                                      title: Text(
                                          isActive ? 'Deactivate' : 'Activate'),
                                      contentPadding: EdgeInsets.zero),
                                ),
                                PopupMenuItem(
                                  onTap: () => _delete(s['id']),
                                  child: const ListTile(
                                      leading: Icon(Icons.delete_outline,
                                          color: Colors.red),
                                      title: Text('Delete',
                                          style:
                                              TextStyle(color: Colors.red)),
                                      contentPadding: EdgeInsets.zero),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}