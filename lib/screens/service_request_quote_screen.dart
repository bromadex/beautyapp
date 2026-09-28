import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';

class ServiceRequestQuoteScreen extends StatefulWidget {
  final String requestId;
  const ServiceRequestQuoteScreen({super.key, required this.requestId});

  @override
  State<ServiceRequestQuoteScreen> createState() =>
      _ServiceRequestQuoteScreenState();
}

class _ServiceRequestQuoteScreenState
    extends State<ServiceRequestQuoteScreen> {
  Map<String, dynamic>? _request;
  List<Map<String, dynamic>> _quotes = [];
  bool _loading = true;
  bool _submitting = false;
  bool _alreadyQuoted = false;

  final _priceCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final uid = supabase.auth.currentUser!.id;

      final req = await supabase
          .from('service_requests')
          .select('*, client:profiles!service_requests_client_id_fkey(full_name), service_categories(name, icon)')
          .eq('id', widget.requestId)
          .single();

      final quotes = await supabase
          .from('service_request_quotes')
          .select('*, provider:profiles!service_request_quotes_provider_id_fkey(full_name)')
          .eq('request_id', widget.requestId)
          .order('created_at', ascending: false);

      final myQuote = quotes.where((q) => q['provider_id'] == uid).toList();

      if (mounted) {
        setState(() {
          _request = req;
          _quotes = List<Map<String, dynamic>>.from(quotes);
          _alreadyQuoted = myQuote.isNotEmpty;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _acceptQuote(Map<String, dynamic> q) async {
    final price = (q['quoted_price'] as num).toStringAsFixed(0);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Accept this quote?'),
        content: Text(
            'A booking request for \$$price will be sent to ${q['provider']?['full_name'] ?? 'the stylist'} '
            'for your preferred date and time. They will confirm it with you.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Accept & Book')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final bookingId = await supabase.rpc('accept_quote', params: {'p_quote_id': q['id']});
      if (mounted) context.go('/booking/$bookingId');
    } on PostgrestException catch (e) {
      if (!mounted) return;
      if (e.message.contains('ACTIVATION_REQUIRED')) {
        context.push('/activation');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _submitQuote() async {
    final price = double.tryParse(_priceCtrl.text);
    if (price == null || price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid price')),
      );
      return;
    }

    setState(() => _submitting = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase.from('service_request_quotes').insert({
        'request_id': widget.requestId,
        'provider_id': uid,
        'quoted_price': price,
        'message': _messageCtrl.text.trim().isEmpty
            ? null
            : _messageCtrl.text.trim(),
        'estimated_duration':
            int.tryParse(_durationCtrl.text),
      });

      final providerName = (await supabase
              .from('profiles')
              .select('full_name')
              .eq('id', uid)
              .maybeSingle())?['full_name'] ??
          'A stylist';

      NotificationService.send(
        userId: _request!['client_id'],
        type: 'quote',
        title: 'New Quote Received',
        body: '$providerName quoted \$${price.toStringAsFixed(0)} for "${_request!['title']}"',
        referenceId: widget.requestId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Quote sent!'),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
        context.pop();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.message), backgroundColor: AppColors.error),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _messageCtrl.dispose();
    _durationCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
          body: Center(child: CircularProgressIndicator()));
    }

    final r = _request!;
    final cat = r['service_categories'] as Map?;
    final budgetMin = (r['budget_min'] as num?)?.toDouble();
    final budgetMax = (r['budget_max'] as num?)?.toDouble();
    final isMyRequest =
        r['client_id'] == supabase.auth.currentUser?.id;

    return Scaffold(
      appBar: AppBar(title: const Text('Request Details')),
      body: SingleChildScrollView(
        padding: AppSpacing.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Request info
            Container(
              padding: AppSpacing.cardPadding,
              decoration: BoxDecoration(
                color: AppColors.cardLight,
                borderRadius: AppRadius.lgAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (cat?['icon'] != null)
                      Text(cat!['icon'],
                          style: const TextStyle(fontSize: 24)),
                    if (cat?['icon'] != null)
                      const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(r['title'] ?? '',
                          style:
                              Theme.of(context).textTheme.titleMedium),
                    ),
                  ]),
                  if (r['description'] != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(r['description'],
                        style: Theme.of(context).textTheme.bodyMedium),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.sm,
                    children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.location_on_outlined,
                            size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(r['location'] ?? '',
                            style: const TextStyle(fontSize: 13)),
                      ]),
                      if (budgetMin != null || budgetMax != null)
                        Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.attach_money_rounded,
                                  size: 16,
                                  color: AppColors.textTertiary),
                              Text(
                                budgetMin != null && budgetMax != null
                                    ? '\$${budgetMin.toStringAsFixed(0)}-\$${budgetMax.toStringAsFixed(0)}'
                                    : budgetMax != null
                                        ? 'Up to \$${budgetMax.toStringAsFixed(0)}'
                                        : 'From \$${budgetMin!.toStringAsFixed(0)}',
                                style: const TextStyle(fontSize: 13),
                              ),
                            ]),
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.person_outline,
                            size: 16, color: AppColors.textTertiary),
                        const SizedBox(width: 4),
                        Text(r['client']?['full_name'] ?? 'Client',
                            style: const TextStyle(fontSize: 13)),
                      ]),
                    ],
                  ),
                ],
              ),
            ),

            // Quotes list
            if (_quotes.isNotEmpty || isMyRequest) ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('Quotes (${_quotes.length})',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              if (_quotes.isEmpty)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  decoration: BoxDecoration(
                    color: AppColors.cardLight,
                    borderRadius: AppRadius.lgAll,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Text('No quotes yet',
                        style: TextStyle(color: AppColors.textTertiary)),
                  ),
                )
              else
                ...(_quotes.map((q) => Card(
                      margin:
                          const EdgeInsets.only(bottom: AppSpacing.sm),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor:
                              AppColors.primary.withValues(alpha: 0.1),
                          child: Text(
                            (q['provider']?['full_name'] ?? '?')[0]
                                .toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                        title: Text(
                            q['provider']?['full_name'] ?? 'Provider'),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                                '\$${(q['quoted_price'] as num).toStringAsFixed(0)}${q['estimated_duration'] != null ? ' · ${q['estimated_duration']} min' : ''}'),
                            if (q['message'] != null)
                              Text(q['message'],
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textTertiary)),
                          ],
                        ),
                        trailing: isMyRequest && q['status'] == 'pending'
                            ? FilledButton(
                                onPressed: () => _acceptQuote(q),
                                style: FilledButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: AppSpacing.md),
                                ),
                                child: const Text('Accept'),
                              )
                            : Text(
                                q['status']?.toString().toUpperCase() ??
                                    'PENDING',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: q['status'] == 'accepted'
                                      ? AppColors.success
                                      : AppColors.textTertiary,
                                ),
                              ),
                      ),
                    ))),
            ],

            // Submit quote form (provider only)
            if (!isMyRequest && !_alreadyQuoted &&
                r['status'] == 'open') ...[
              const SizedBox(height: AppSpacing.xxl),
              Text('Send Your Quote',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: AppSpacing.md),
              TextField(
                controller: _priceCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Your Price (\$)',
                  prefixIcon: const Icon(Icons.attach_money_rounded),
                  border:
                      OutlineInputBorder(borderRadius: AppRadius.mdAll),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _durationCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Estimated Duration (min)',
                  prefixIcon: const Icon(Icons.timer_outlined),
                  border:
                      OutlineInputBorder(borderRadius: AppRadius.mdAll),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(
                controller: _messageCtrl,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Message to client (optional)',
                  border:
                      OutlineInputBorder(borderRadius: AppRadius.mdAll),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _submitting ? null : _submitQuote,
                icon: _submitting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                label: Text(
                    _submitting ? 'Sending...' : 'Send Quote'),
              ),
            ],

            if (_alreadyQuoted) ...[
              const SizedBox(height: AppSpacing.xxl),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: AppRadius.mdAll,
                  border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded,
                      color: AppColors.success, size: 22),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(
                    child: Text('You have already quoted on this request'),
                  ),
                ]),
              ),
            ],

            const SizedBox(height: AppSpacing.xxl),
          ],
        ),
      ),
    );
  }
}
