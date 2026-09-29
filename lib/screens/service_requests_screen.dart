import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class ServiceRequestsScreen extends StatefulWidget {
  final bool isProvider;
  const ServiceRequestsScreen({super.key, this.isProvider = false});

  @override
  State<ServiceRequestsScreen> createState() => _ServiceRequestsScreenState();
}

class _ServiceRequestsScreenState extends State<ServiceRequestsScreen> {
  List<Map<String, dynamic>> _requests = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      List<Map<String, dynamic>> data;

      if (widget.isProvider) {
        data = await supabase
            .from('service_requests')
            .select('*, client:profiles!service_requests_client_id_fkey(full_name), service_categories(name, icon)')
            .eq('status', 'open')
            .order('created_at', ascending: false);
      } else {
        data = await supabase
            .from('service_requests')
            .select('*, service_categories(name, icon)')
            .eq('client_id', uid!)
            .order('created_at', ascending: false);
      }
      if (mounted) setState(() { _requests = data; _loading = false; });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isProvider ? 'Service Requests' : 'My Requests'),
      ),
      floatingActionButton: widget.isProvider
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                await context.push('/service-request/create');
                _load();
              },
              icon: const Icon(TablerIcons.plus),
              label: const Text('New Request'),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.onPrimary,
            ),
      body: _loading
          ? const LoadingPlaceholder()
          : _requests.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(TablerIcons.search_off,
                          size: 64, color: AppColors.textTertiary),
                      const SizedBox(height: AppSpacing.lg),
                      Text(
                        widget.isProvider
                            ? 'No open requests nearby'
                            : 'No requests yet',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.isProvider
                            ? 'Check back later for client requests'
                            : 'Post a request and let beauty pros come to you',
                        style: TextStyle(color: AppColors.textTertiary),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: AppSpacing.screenPadding,
                    itemCount: _requests.length,
                    itemBuilder: (_, i) =>
                        _RequestCard(request: _requests[i], isProvider: widget.isProvider),
                  ),
                ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> request;
  final bool isProvider;
  const _RequestCard({required this.request, required this.isProvider});

  @override
  Widget build(BuildContext context) {
    final cat = request['service_categories'] as Map?;
    final status = request['status'] as String? ?? 'open';
    final budgetMin = (request['budget_min'] as num?)?.toDouble();
    final budgetMax = (request['budget_max'] as num?)?.toDouble();
    final createdAt = DateTime.tryParse(request['created_at'] ?? '')?.toLocal();
    final dateStr = createdAt != null
        ? '${createdAt.day}/${createdAt.month}/${createdAt.year}'
        : '';

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () {
          if (isProvider) {
            context.push('/service-request/${request['id']}/quote');
          } else {
            context.push('/service-request/${request['id']}');
          }
        },
        borderRadius: AppRadius.lgAll,
        child: Padding(
          padding: AppSpacing.cardPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CategoryBadge(name: cat?['name'], size: 40),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(request['title'] ?? '',
                        style: Theme.of(context).textTheme.titleSmall),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 2),
                    decoration: BoxDecoration(
                      color: StatusColors.background(status),
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: StatusColors.foreground(status),
                      ),
                    ),
                  ),
                ],
              ),
              if (request['description'] != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  request['description'],
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13, color: AppColors.textSecondary),
                ),
              ],
              const SizedBox(height: AppSpacing.md),
              Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.xs,
                children: [
                  if (request['location'] != null)
                    _InfoChip(
                      icon: TablerIcons.map_pin,
                      label: request['location'],
                    ),
                  if (budgetMin != null || budgetMax != null)
                    _InfoChip(
                      icon: TablerIcons.currency_dollar,
                      label: budgetMin != null && budgetMax != null
                          ? '\$${budgetMin.toStringAsFixed(0)}-\$${budgetMax.toStringAsFixed(0)}'
                          : budgetMax != null
                              ? 'Up to \$${budgetMax.toStringAsFixed(0)}'
                              : 'From \$${budgetMin!.toStringAsFixed(0)}',
                    ),
                  _InfoChip(icon: TablerIcons.calendar, label: dateStr),
                ],
              ),
              if (isProvider && request['client']?['full_name'] != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'by ${request['client']['full_name']}',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textTertiary),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
      ],
    );
  }
}
