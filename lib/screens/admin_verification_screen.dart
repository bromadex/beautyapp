import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  State<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState
    extends State<AdminVerificationScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await supabase
        .from('verifications')
        .select('*, profiles(full_name, user_type, phone)')
        .eq('status', 'pending')
        .order('submitted_at');
    if (mounted) {
      setState(() {
        _pending = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<String> _getSignedUrl(String path) async {
    final res = await supabase.storage
        .from('verification-docs')
        .createSignedUrl(path, 60); // valid for 60 seconds
    return res;
  }

  Future<void> _review(
      String verificationId, String userId, bool approve,
      {String? note}) async {
    // Update verification status
    await supabase.from('verifications').update({
      'status':      approve ? 'approved' : 'rejected',
      'admin_note':  note,
      'reviewed_at': DateTime.now().toIso8601String(),
    }).eq('id', verificationId);

    // If approved, set profile is_verified = true
    if (approve) {
      await supabase
          .from('profiles')
          .update({'is_verified': true})
          .eq('id', userId);
    }

    _load();
  }

  void _showRejectDialog(
      String verificationId, String userId) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Reject Submission'),
        content: TextField(
          controller: noteCtrl,
          decoration: const InputDecoration(
            labelText: 'Reason (shown to user)',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _review(verificationId, userId, false,
                  note: noteCtrl.text.trim());
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
  }

  void _showDocuments(
      String selfiePath, String idPath) async {
    // Get signed URLs
    showDialog(
      context: context,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 80,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );

    final selfieUrl = await _getSignedUrl(selfiePath);
    final idUrl     = await _getSignedUrl(idPath);

    if (!mounted) return;
    Navigator.pop(context); // close loading dialog

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Submitted Documents'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Selfie:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Image.network(selfieUrl),
              const SizedBox(height: 16),
              const Text('ID Document:',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Image.network(idUrl),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — Verifications'),
        actions: [
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _pending.isEmpty
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline,
                          size: 64, color: Colors.green),
                      SizedBox(height: 16),
                      Text('No pending verifications'),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _pending.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (_, i) {
                    final v       = _pending[i];
                    final profile = v['profiles'] as Map<String, dynamic>;
                    final name    = profile['full_name'] ?? 'Unknown';
                    final type    = profile['user_type'] ?? '';
                    final phone   = profile['phone'] ?? '';
                    final submittedAt = DateTime.tryParse(
                        v['submitted_at'] ?? '');

                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  child: Text(
                                      name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?'),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(name,
                                          style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15)),
                                      Text(
                                          '$type · $phone',
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12)),
                                      if (submittedAt != null)
                                        Text(
                                          'Submitted: ${submittedAt.toLocal().toString().substring(0, 16)}',
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 11),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            // View docs button
                            OutlinedButton.icon(
                              onPressed: () => _showDocuments(
                                  v['selfie_url'], v['id_document_url']),
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('View Documents'),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    onPressed: () => _showRejectDialog(
                                        v['id'], v['user_id']),
                                    icon: const Icon(Icons.close,
                                        color: Colors.red),
                                    label: const Text('Reject',
                                        style:
                                            TextStyle(color: Colors.red)),
                                    style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Colors.red)),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: () => _review(
                                        v['id'], v['user_id'], true),
                                    icon: const Icon(Icons.check),
                                    label: const Text('Approve'),
                                    style: FilledButton.styleFrom(
                                        backgroundColor: Colors.green),
                                  ),
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