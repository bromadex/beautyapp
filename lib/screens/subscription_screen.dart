import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});
  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  Map<String, dynamic>? _subscription;
  bool _loading = true;
  bool _processing = false;
  String? _error;

  static const _plans = [
    {'label': '1 Month',  'months': 1,  'price': 10.00},
    {'label': '3 Months', 'months': 3,  'price': 27.00},
    {'label': '6 Months', 'months': 6,  'price': 50.00},
  ];

  int _selectedPlan = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    
    try {
      final userId = supabase.auth.currentUser!.id;
      
      final data = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();
          
      if (mounted) {
        setState(() { 
          _subscription = data; 
          _loading = false; 
        });
      }
    } catch (e) {
      print('Error loading subscription: $e');
      if (mounted) {
        setState(() { 
          _error = e.toString(); 
          _loading = false; 
        });
      }
    }
  }

  bool get _isActive {
    if (_subscription == null) return false;
    if (_subscription!['status'] != 'active') return false;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    return end != null && end.isAfter(DateTime.now());
  }

  int get _daysRemaining {
    if (_subscription == null) return 0;
    final end = DateTime.tryParse(_subscription!['end_date'] ?? '');
    if (end == null) return 0;
    final diff = end.difference(DateTime.now()).inDays;
    return diff.clamp(0, 9999);
  }

  Future<void> _subscribe() async {
    setState(() => _processing = true);

    try {
      final userId = supabase.auth.currentUser!.id;
      final plan = _plans[_selectedPlan];
      final months = plan['months'] as int;
      final price = plan['price'] as double;

      final startDate = DateTime.now();
      final endDate = DateTime(startDate.year, startDate.month + months, startDate.day);

      final payload = {
        'provider_id': userId,
        'start_date': startDate.toIso8601String().split('T')[0],
        'end_date': endDate.toIso8601String().split('T')[0],
        'status': 'active',
        'plan': '${months}_month',
        'amount_paid': price,
        'payment_ref': 'SIM-${DateTime.now().millisecondsSinceEpoch}',
      };

      final existing = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();

      if (existing == null) {
        await supabase.from('subscriptions').insert(payload);
      } else {
        await supabase.from('subscriptions').update(payload).eq('provider_id', userId);
      }

      await supabase
          .from('provider_profiles')
          .update({'is_hidden': false})
          .eq('provider_id', userId);

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Subscription activated! Valid for $months month(s) ✓'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      print('Subscribe error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _debugExpire() async {
    try {
      final userId = supabase.auth.currentUser!.id;
      final yesterday = DateTime.now().subtract(const Duration(days: 1));

      await supabase.from('subscriptions').update({
        'end_date': yesterday.toIso8601String().split('T')[0],
        'status': 'expired',
      }).eq('provider_id', userId);

      await supabase.from('provider_profiles')
          .update({'is_hidden': true})
          .eq('provider_id', userId);

      await _load();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('DEBUG: Subscription expired & profile hidden'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      print('Debug expire error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Subscription')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('My Subscription')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $_error', textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _load,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('My Subscription')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _StatusCard(
              isActive: _isActive,
              daysRemaining: _daysRemaining,
              subscription: _subscription,
            ),
            const SizedBox(height: 32),
            Text(
              _isActive ? 'Renew / Upgrade Plan' : 'Choose a Plan',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._plans.asMap().entries.map((entry) {
              final i = entry.key;
              final plan = entry.value;
              final isSelected = _selectedPlan == i;
              final months = plan['months'] as int;
              final price = plan['price'] as double;
              final perMonth = (price / months).toStringAsFixed(2);

              return GestureDetector(
                onTap: () => setState(() => _selectedPlan = i),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Theme.of(context).colorScheme.primaryContainer
                        : null,
                    border: Border.all(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey.shade300,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Radio<int>(
                        value: i,
                        groupValue: _selectedPlan,
                        onChanged: (v) => setState(() => _selectedPlan = v!),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plan['label'] as String,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold, fontSize: 15)),
                            Text('\$$perMonth / month',
                                style: const TextStyle(
                                    color: Colors.grey, fontSize: 13)),
                          ],
                        ),
                      ),
                      if (months == 3)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.green.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Save 10%',
                              style: TextStyle(
                                  color: Colors.green.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      if (months == 6)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('Save 17%',
                              style: TextStyle(
                                  color: Colors.purple.shade800,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold)),
                        ),
                      const SizedBox(width: 8),
                      Text(
                        '\$${price.toStringAsFixed(2)}',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Theme.of(context).colorScheme.primary),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment is simulated for now. Real payment integration (PayStack/Stripe) comes in Stage 8.',
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _processing ? null : _subscribe,
              icon: _processing
                  ? const SizedBox(
                      height: 18, width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.payment_rounded),
              label: Text(
                _processing
                    ? 'Processing...'
                    : _isActive
                        ? 'Renew Subscription — \$${(_plans[_selectedPlan]['price'] as double).toStringAsFixed(2)}'
                        : 'Subscribe Now — \$${(_plans[_selectedPlan]['price'] as double).toStringAsFixed(2)}',
              ),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            ),
            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),
            Text('🛠 Debug Tools (remove before production)',
                style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _debugExpire,
              icon: const Icon(Icons.timer_off_outlined, color: Colors.orange),
              label: const Text('Simulate Expiry', style: TextStyle(color: Colors.orange)),
              style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange)),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  final bool isActive;
  final int daysRemaining;
  final Map<String, dynamic>? subscription;

  const _StatusCard({
    required this.isActive,
    required this.daysRemaining,
    required this.subscription,
  });

  @override
  Widget build(BuildContext context) {
    if (subscription == null) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Column(
          children: [
            Icon(Icons.lock_outline, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text('No Active Subscription',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            SizedBox(height: 4),
            Text(
              'Subscribe to appear in client searches and accept bookings.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    final endDate = DateTime.tryParse(subscription!['end_date'] ?? '');
    final endStr = endDate != null
        ? '${endDate.day}/${endDate.month}/${endDate.year}'
        : 'Unknown';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isActive
              ? [Colors.green.shade400, Colors.green.shade600]
              : [Colors.red.shade400, Colors.red.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
              isActive ? Icons.verified_rounded : Icons.warning_rounded,
              color: Colors.white,
              size: 28,
            ),
            const SizedBox(width: 10),
            Text(
              isActive ? 'Subscription Active' : 'Subscription Expired',
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
            ),
          ]),
          const SizedBox(height: 12),
          if (isActive) ...[
            Text('$daysRemaining days remaining',
                style: const TextStyle(
                    color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Expires $endStr',
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ] else ...[
            Text('Expired on $endStr',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 4),
            const Text(
              'Your profile is hidden from clients. Renew to restore visibility.',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ],
      ),
    );
  }
}