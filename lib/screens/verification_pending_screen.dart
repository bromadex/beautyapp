import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState
    extends State<VerificationPendingScreen> {
  Map<String, dynamic>? _verification;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = supabase.auth.currentUser!.id;
    try {
      final data = await supabase
          .from('verifications')
          .select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1)
          .single();
      if (mounted) setState(() => _verification = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final status = _verification?['status'] ?? 'pending';
    final adminNote = _verification?['admin_note'];

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(
              status == 'rejected'
                  ? Icons.cancel_rounded
                  : Icons.hourglass_top_rounded,
              size: 80,
              color: status == 'rejected'
                  ? Colors.red
                  : Colors.orange,
            ),
            const SizedBox(height: 24),
            Text(
              status == 'rejected'
                  ? 'Verification Rejected'
                  : 'Under Review',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              status == 'rejected'
                  ? 'Your submission was not approved. Please re-submit with clearer photos.'
                  : 'Your documents have been submitted and are being reviewed. This usually takes 24 hours.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey, fontSize: 14),
            ),
            if (adminNote != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Admin note: $adminNote',
                    style: TextStyle(
                        color: Colors.red.shade700, fontSize: 13)),
              ),
            ],
            const SizedBox(height: 32),
            if (status == 'rejected')
              FilledButton(
                onPressed: () => context.go('/verify'),
                child: const Text('Re-Submit Documents'),
              ),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Back to Home'),
            ),
          ],
        ),
      ),
    );
  }
}