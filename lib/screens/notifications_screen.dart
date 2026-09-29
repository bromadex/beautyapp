import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/ui.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});
  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _notifications = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final userId = supabase.auth.currentUser!.id;
    try {
      final data = await supabase
          .from('notifications')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(50);
      if (mounted) {
        setState(() {
          _notifications = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markAllRead() async {
    final userId = supabase.auth.currentUser!.id;
    await supabase
        .from('notifications')
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
    _load();
  }

  Future<void> _markRead(String id) async {
    await supabase
        .from('notifications')
        .update({'is_read': true}).eq('id', id);
  }

  void _onTap(Map<String, dynamic> n) {
    if (n['is_read'] != true) _markRead(n['id']);

    final type = n['type'] ?? '';
    final refId = n['reference_id'];

    if (refId == null) {
      if (type == 'products') context.push('/provider/products');
      return;
    }

    switch (type) {
      case 'booking':
      case 'booking_status':
        context.push('/booking/$refId');
        break;
      case 'payment':
        context.push('/booking/$refId');
        break;
      case 'review':
        final userId = supabase.auth.currentUser!.id;
        context.push('/provider/$userId/reviews');
        break;
      case 'message':
        context.push('/chat/$refId');
        break;
      case 'promotion':
        context.push('/provider/promotions');
        break;
      case 'review_request':
        context.push('/review/$refId');
        break;
      case 'service_review':
        context.push('/provider/services');
        break;
      case 'fee_update':
        context.push('/provider/subscription');
        break;
      case 'fee_claim':
        context.push('/admin/fees');
        break;
      case 'referral':
        context.push('/provider/referrals');
        break;
      case 'salon':
        context.push('/provider/salon');
        break;
      case 'products':
        context.push('/provider/products');
        break;
      case 'waitlist':
        final parts = refId.toString().split('|');
        final serviceId = parts.length > 1 ? parts[1] : '';
        context.push(serviceId.isEmpty ? '/provider/${parts[0]}' : '/book/${parts[0]}/$serviceId');
        break;
    }
  }

  IconData _iconForType(String type) {
    switch (type) {
      case 'booking':
        return TablerIcons.calendar_month;
      case 'booking_status':
        return TablerIcons.clock_edit;
      case 'payment':
        return TablerIcons.credit_card;
      case 'review':
        return TablerIcons.star_filled;
      case 'message':
        return TablerIcons.message_circle;
      case 'promotion':
        return TablerIcons.tag;
      case 'review_request':
        return TablerIcons.message_star;
      case 'waitlist':
        return TablerIcons.calendar_check;
      default:
        return TablerIcons.bell;
    }
  }

  Color _colorForType(String type) {
    switch (type) {
      case 'booking':
        return AppColors.info;
      case 'booking_status':
        return AppColors.secondary;
      case 'payment':
        return AppColors.success;
      case 'review':
        return AppColors.warning;
      case 'message':
        return AppColors.primary;
      case 'promotion':
        return AppColors.accent;
      case 'review_request':
        return AppColors.warning;
      case 'waitlist':
        return AppColors.success;
      default:
        return AppColors.textTertiary;
    }
  }

  String _timeAgo(String? iso) {
    if (iso == null) return '';
    final dt = DateTime.tryParse(iso)?.toLocal();
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final unreadCount =
        _notifications.where((n) => n['is_read'] != true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllRead,
              icon: const Icon(TablerIcons.checks, size: 18),
              label: const Text('Read All'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
              ),
            ),
        ],
      ),
      body: _loading
          ? const LoadingPlaceholder()
          : _notifications.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    itemCount: _notifications.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: AppSpacing.xs),
                    itemBuilder: (_, i) =>
                        _buildNotificationCard(_notifications[i]),
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.xl),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(TablerIcons.bell_off,
                size: 56, color: AppColors.primary),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('No Notifications',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary)),
          const SizedBox(height: AppSpacing.sm),
          Text("You're all caught up!",
              style:
                  TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> n) {
    final isRead = n['is_read'] == true;
    final type = n['type'] ?? '';
    final color = _colorForType(type);

    return Material(
      color: isRead ? Colors.white : color.withValues(alpha: 0.03),
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        onTap: () => _onTap(n),
        borderRadius: AppRadius.mdAll,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.lg),
          decoration: BoxDecoration(
            borderRadius: AppRadius.mdAll,
            border: Border.all(
              color: isRead
                  ? AppColors.border
                  : color.withValues(alpha: 0.2),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Icon(_iconForType(type), color: color, size: 20),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            n['title'] ?? '',
                            style: TextStyle(
                              fontWeight:
                                  isRead ? FontWeight.w500 : FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        if (!isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      n['body'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      _timeAgo(n['created_at']),
                      style: TextStyle(
                          fontSize: 11, color: AppColors.textTertiary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
