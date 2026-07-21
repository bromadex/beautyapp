import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AdminBookingsScreen extends StatefulWidget {
  const AdminBookingsScreen({super.key});

  @override
  State<AdminBookingsScreen> createState() => _AdminBookingsScreenState();
}

class _AdminBookingsScreenState extends State<AdminBookingsScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _bookings = [];
  String _statusFilter = 'all';

  final _statusOptions = ['all', 'pending', 'confirmed', 'en_route', 'arrived', 'in_progress', 'completed', 'cancelled'];

  @override
  void initState() {
    super.initState();
    _checkAdminAndLoad();
  }

  Future<void> _checkAdminAndLoad() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    final adminRows = await supabase.from('admins').select().eq('user_id', userId);
    if ((adminRows as List).isEmpty) {
      if (mounted) context.go('/home');
      return;
    }
    await _loadBookings();
  }

  Future<void> _loadBookings() async {
    setState(() => _loading = true);
    try {
      var query = supabase
          .from('bookings')
          .select('*, services(service_name), profiles!bookings_client_id_fkey(full_name), provider:profiles!bookings_provider_id_fkey(full_name)');

      if (_statusFilter != 'all') {
        query = query.eq('status', _statusFilter);
      }

      final data = await query.order('created_at', ascending: false).limit(100);

      if (mounted) {
        setState(() {
          _bookings = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _cancelBooking(Map<String, dynamic> booking) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: const Text('Cancel Booking?'),
        content: const Text('This will cancel the booking. This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('No')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Cancel Booking'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase.from('bookings').update({'status': 'cancelled'}).eq('id', booking['id']);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Booking cancelled'), backgroundColor: AppColors.warning),
      );
      _loadBookings();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('All Bookings'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded), onPressed: _loadBookings),
        ],
      ),
      body: Column(
        children: [
          // Status filter chips
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              children: _statusOptions.map((s) {
                final isSelected = _statusFilter == s;
                final label = s == 'all' ? 'All' : StatusColors.label(s);
                return Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.sm),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(label),
                    onSelected: (_) {
                      setState(() => _statusFilter = s);
                      _loadBookings();
                    },
                    selectedColor: s == 'all' ? AppColors.primary.withValues(alpha: 0.1) : StatusColors.background(s),
                    checkmarkColor: s == 'all' ? AppColors.primary : StatusColors.foreground(s),
                    labelStyle: TextStyle(
                      color: isSelected
                          ? (s == 'all' ? AppColors.primary : StatusColors.foreground(s))
                          : AppColors.textSecondary,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
          else if (_bookings.isEmpty)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 48, color: AppColors.textTertiary),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _statusFilter == 'all' ? 'No bookings yet' : 'No ${StatusColors.label(_statusFilter).toLowerCase()} bookings',
                      style: const TextStyle(color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            )
          else
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadBookings,
                child: ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: _bookings.length,
                  separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) => _buildBookingCard(_bookings[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBookingCard(Map<String, dynamic> b) {
    final clientName = b['profiles']?['full_name'] ?? 'Unknown Client';
    final providerName = b['provider']?['full_name'] ?? 'Unknown Provider';
    final serviceName = b['services']?['service_name'] ?? 'Service';
    final status = b['status'] ?? 'pending';
    final price = b['total_price'];
    final date = b['booking_date'] ?? '';
    final time = b['booking_time'] ?? '';
    final canCancel = !['completed', 'cancelled'].contains(status);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => context.push('/booking/${b['id']}'),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          serviceName,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: StatusColors.background(status),
                          borderRadius: AppRadius.smAll,
                        ),
                        child: Text(
                          StatusColors.label(status),
                          style: TextStyle(
                            color: StatusColors.foreground(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Client: $clientName', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.spa_outlined, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text('Provider: $providerName', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.schedule_rounded, size: 14, color: AppColors.textTertiary),
                      const SizedBox(width: AppSpacing.xs),
                      Text('$date at $time', style: const TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                      const Spacer(),
                      if (price != null)
                        Text(
                          'R${(price as num).toStringAsFixed(0)}',
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: AppColors.primary),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (canCancel) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _cancelBooking(b),
                    icon: const Icon(Icons.cancel_outlined, size: 16),
                    label: const Text('Cancel'),
                    style: TextButton.styleFrom(foregroundColor: AppColors.error),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
