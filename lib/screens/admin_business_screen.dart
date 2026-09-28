import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';

class AdminBusinessScreen extends StatefulWidget {
  const AdminBusinessScreen({super.key});

  @override
  State<AdminBusinessScreen> createState() => _AdminBusinessScreenState();
}

class _AdminBusinessScreenState extends State<AdminBusinessScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('business_verifications')
          .select('*, profiles!business_verifications_provider_id_fkey(full_name, phone)')
          .eq('status', 'pending')
          .order('submitted_at');
      if (mounted) {
        setState(() {
          _items = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _review(Map<String, dynamic> v, bool approve) async {
    String? note;
    if (!approve) {
      final ctrl = TextEditingController();
      note = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Reason for rejection'),
          content: TextField(controller: ctrl, maxLines: 2,
              decoration: const InputDecoration(hintText: 'e.g. Registration number not found')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Reject')),
          ],
        ),
      );
      if (note == null) return;
    }
    try {
      await supabase.rpc('review_business_verification', params: {
        'p_id': v['id'],
        'p_approve': approve,
        'p_note': note,
      });
      _load();
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(e.message), backgroundColor: AppColors.error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Business Verifications')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _items.isEmpty
              ? Center(child: Text('Nothing waiting for review',
                  style: Theme.of(context).textTheme.bodyMedium))
              : ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: _items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) {
                    final v = _items[i];
                    return Card(
                      child: Padding(
                        padding: AppSpacing.cardPadding,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(v['business_name'] ?? 'Unnamed business',
                              style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text('Owner: ${v['profiles']?['full_name'] ?? '—'}'
                              '${v['profiles']?['phone'] != null ? ' · ${v['profiles']['phone']}' : ''}',
                              style: Theme.of(context).textTheme.bodyMedium),
                          Text('Registration no.: ${v['registration_number'] ?? '—'}',
                              style: Theme.of(context).textTheme.bodyMedium),
                          const SizedBox(height: AppSpacing.md),
                          Row(children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _review(v, false),
                                child: const Text('Reject'),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: FilledButton(
                                onPressed: () => _review(v, true),
                                child: const Text('Approve'),
                              ),
                            ),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
    );
  }
}
