import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/app_config.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme.dart';

class ProviderHomeScreen extends StatefulWidget {
  const ProviderHomeScreen({super.key});
  @override
  State<ProviderHomeScreen> createState() => _ProviderHomeScreenState();
}

class _ProviderHomeScreenState extends State<ProviderHomeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _verification;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _subscription;
  bool _isAdmin = false;
  bool _loading = true;
  late AnimationController _animCtrl;
  RealtimeChannel? _subChannel;
  RealtimeChannel? _verifyChannel;

  Map<String, dynamic>? _nextBooking;
  double _weeklyEarnings = 0;
  double _prevWeekEarnings = 0;
  int _weeklyBookingsCount = 0;
  int _pendingBookingsCount = 0;
  int _totalBookingsCount = 0;
  int _totalReviews = 0;
  double _avgRating = 0;
  int _unreadMessages = 0;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _subscribeRealtime();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) PushService.maybeInit(context);
    });
  }

  void _subscribeRealtime() {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;

    _subChannel = supabase
        .channel('home_subscriptions')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'subscriptions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'provider_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();

    _verifyChannel = supabase
        .channel('home_verifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'verifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            _loadData();
            final newRecord = payload.newRecord;
            if (newRecord['status'] == 'approved') {
              _showVerifiedDialog();
            }
          },
        )
        .subscribe();
  }

  void _showVerifiedDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        icon: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.success.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.verified_rounded,
              color: AppColors.success, size: 48),
        ),
        title: const Text('Well Done!'),
        content: const Text(
          'Your identity has been verified. You now have full access to all provider features.',
          textAlign: TextAlign.center,
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
            },
            child: const Text('Let\'s Go!'),
          ),
        ],
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _loadData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _subChannel?.unsubscribe();
    _verifyChannel?.unsubscribe();
    _animCtrl.dispose();
    super.dispose();
  }

  void _shareProfile(BuildContext context) {
    final uid = supabase.auth.currentUser!.id;
    final profileUrl = '${AppConfig.webBaseUrl}/#/provider/$uid';
    final name = _profile?['full_name'] ?? 'my';

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            const Text('Share Your Profile', style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
            )),
            const SizedBox(height: AppSpacing.sm),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: AppRadius.mdAll,
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      profileUrl,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 20),
                    color: AppColors.primary,
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: profileUrl));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: const Text('Link copied to clipboard!'),
                          backgroundColor: AppColors.success,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.pop(context);
                  SharePlus.instance.share(
                    ShareParams(
                      title: 'Book $name on BeauTap',
                      uri: Uri.parse(profileUrl),
                    ),
                  );
                },
                icon: const Icon(Icons.share_rounded, size: 18),
                label: const Text('Share to Apps'),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ),
      ),
    );
  }

  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    Map<String, dynamic> profile;
    try {
      profile = await supabase
          .from('profiles').select().eq('id', userId).single();
    } catch (_) {
      await supabase.auth.signOut();
      if (mounted) context.go('/login');
      return;
    }

    final adminRows = await supabase
        .from('admins').select().eq('user_id', userId);
    final isAdmin = (adminRows as List).isNotEmpty;

    Map<String, dynamic>? verification;
    try {
      verification = await supabase
          .from('verifications').select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1).single();
    } catch (_) {}

    Map<String, dynamic>? providerProfile;
    Map<String, dynamic>? subscription;
    Map<String, dynamic>? nextBooking;
    double weeklyEarnings = 0;
    double prevWeekEarnings = 0;
    int weeklyBookingsCount = 0;
    int pendingBookingsCount = 0;
    int totalBookingsCount = 0;
    int totalReviews = 0;
    double avgRating = 0;
    int unreadMessages = 0;
    int unreadNotifs = 0;
    List<Map<String, dynamic>> recentActivity = [];

    try {
      providerProfile = await supabase
          .from('provider_profiles').select()
          .eq('provider_id', userId).single();
    } catch (_) {}

    try {
      subscription = await supabase
          .from('subscriptions')
          .select()
          .eq('provider_id', userId)
          .maybeSingle();
    } catch (_) {}

    try {
      final now = DateTime.now().toIso8601String();
      nextBooking = await supabase
          .from('bookings')
          .select('*, services(service_name, duration_minutes), profiles!bookings_client_id_fkey(full_name)')
          .eq('provider_id', userId)
          .inFilter('status', ['confirmed', 'en_route', 'arrived', 'in_progress'])
          .gte('booking_date', now.substring(0, 10))
          .order('booking_date', ascending: true)
          .order('booking_time', ascending: true)
          .limit(1)
          .maybeSingle();
    } catch (_) {}

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7)).toIso8601String();
      final twoWeeksAgo = now.subtract(const Duration(days: 14)).toIso8601String();

      final payments = await supabase
          .from('payments')
          .select('amount, created_at')
          .eq('provider_id', userId)
          .eq('status', 'completed')
          .gte('created_at', twoWeeksAgo);

      for (final p in (payments as List)) {
        final amount = (p['amount'] as num).toDouble();
        final createdAt = p['created_at'] as String;
        if (createdAt.compareTo(weekAgo) >= 0) {
          weeklyEarnings += amount;
        } else {
          prevWeekEarnings += amount;
        }
      }
    } catch (_) {}

    try {
      final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
      final bookings = await supabase
          .from('bookings')
          .select('id, status')
          .eq('provider_id', userId)
          .gte('created_at', weekAgo);
      weeklyBookingsCount = (bookings as List).length;
      pendingBookingsCount = bookings.where((b) => b['status'] == 'pending' || b['status'] == 'confirmed').length;
    } catch (_) {}

    try {
      final allBookings = await supabase
          .from('bookings')
          .select('id')
          .eq('provider_id', userId);
      totalBookingsCount = (allBookings as List).length;
    } catch (_) {}

    try {
      final reviews = await supabase
          .from('reviews')
          .select('rating')
          .eq('provider_id', userId);
      final list = reviews as List;
      totalReviews = list.length;
      if (list.isNotEmpty) {
        double sum = 0;
        for (final r in list) sum += (r['rating'] as num).toDouble();
        avgRating = sum / list.length;
      }
    } catch (_) {}

    try {
      final msgs = await supabase
          .from('messages')
          .select('id')
          .eq('receiver_id', userId)
          .eq('is_read', false);
      unreadMessages = (msgs as List).length;
    } catch (_) {}

    try {
      final recentReviews = await supabase
          .from('reviews')
          .select('id, rating, comment, created_at, profiles!reviews_client_id_fkey(full_name)')
          .eq('provider_id', userId)
          .order('created_at', ascending: false)
          .limit(3);
      for (final r in (recentReviews as List)) {
        recentActivity.add({'type': 'review', 'data': r, 'created_at': r['created_at']});
      }
    } catch (_) {}

    try {
      final recentPayments = await supabase
          .from('payments')
          .select('id, amount, created_at, bookings(services(service_name), profiles!bookings_client_id_fkey(full_name))')
          .eq('provider_id', userId)
          .eq('status', 'completed')
          .order('created_at', ascending: false)
          .limit(3);
      for (final p in (recentPayments as List)) {
        recentActivity.add({'type': 'payment', 'data': p, 'created_at': p['created_at']});
      }
    } catch (_) {}

    try {
      final recentBookings = await supabase
          .from('bookings')
          .select('id, status, booking_date, booking_time, created_at, services(service_name), profiles!bookings_client_id_fkey(full_name)')
          .eq('provider_id', userId)
          .order('created_at', ascending: false)
          .limit(3);
      for (final b in (recentBookings as List)) {
        recentActivity.add({'type': 'booking', 'data': b, 'created_at': b['created_at']});
      }
    } catch (_) {}

    recentActivity.sort((a, b) =>
        (b['created_at'] as String).compareTo(a['created_at'] as String));
    if (recentActivity.length > 5) recentActivity = recentActivity.sublist(0, 5);

    try {
      unreadNotifs = await NotificationService.unreadCount(userId);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _profile = profile;
        _verification = verification;
        _providerProfile = providerProfile;
        _subscription = subscription;
        _isAdmin = isAdmin;
        _nextBooking = nextBooking;
        _weeklyEarnings = weeklyEarnings;
        _prevWeekEarnings = prevWeekEarnings;
        _weeklyBookingsCount = weeklyBookingsCount;
        _pendingBookingsCount = pendingBookingsCount;
        _totalBookingsCount = totalBookingsCount;
        _totalReviews = totalReviews;
        _avgRating = avgRating;
        _unreadMessages = unreadMessages;
        _unreadNotifications = unreadNotifs;
        _recentActivity = recentActivity;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 40, height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary)),
              const SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final name = _profile?['full_name'] ?? 'User';
    final isVerified = _profile?['is_verified'] == true;
    final vStatus = _verification?['status'];
    final bool hasActiveSubscription = _subscription != null &&
        _subscription!['status'] == 'active';

    return Scaffold(
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            backgroundColor: AppColors.primary,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: const BrandTitle(),
            actions: [
              if (_isAdmin)
                IconButton(
                  icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
                  tooltip: 'Admin Panel',
                  onPressed: () => context.push('/admin/dashboard'),
                ),
              Stack(
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined, color: Colors.white),
                    onPressed: () => context.push('/notifications'),
                  ),
                  if (_unreadNotifications > 0)
                    Positioned(
                      right: 8, top: 8,
                      child: Container(
                        width: 16, height: 16,
                        decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                        child: Center(
                          child: Text(
                            _unreadNotifications > 9 ? '9+' : '$_unreadNotifications',
                            style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.logout_rounded, color: Colors.white70),
                onPressed: _signOut,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(gradient: AppColors.heroGradient),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 56, 20, 16),
                    child: GestureDetector(
                      onTap: () => context.push('/account/settings'),
                      child: Row(
                        children: [
                          Container(
                            width: 50, height: 50,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white38, width: 2),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Welcome back,', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
                                Text(name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: Colors.white)),
                                const SizedBox(height: 5),
                                Row(children: [
                                  if (_avgRating > 0) ...[
                                    const Icon(Icons.star_rounded, color: Colors.amber, size: 16),
                                    const SizedBox(width: 3),
                                    Text(_avgRating.toStringAsFixed(1),
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                                    const SizedBox(width: 12),
                                  ],
                                  Icon(Icons.calendar_month_rounded, color: Colors.white.withValues(alpha: 0.8), size: 14),
                                  const SizedBox(width: 3),
                                  Text('$_totalBookingsCount bookings',
                                    style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.85))),
                                ]),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isVerified) ...[
                          _VerificationBanner(
                            status: vStatus,
                            onTap: () {
                              if (vStatus == null || vStatus == 'rejected') {
                                context.push('/verify');
                              } else {
                                context.push('/verify/pending');
                              }
                            },
                          ),
                          const SizedBox(height: 14),
                        ],

                        if (isVerified) ...[
                          if (_providerProfile != null) ...[
                            _AvailabilityToggle(
                              status: _providerProfile!['availability_status'],
                              onChanged: (newStatus) async {
                                await supabase
                                    .from('provider_profiles')
                                    .update({'availability_status': newStatus})
                                    .eq('provider_id', supabase.auth.currentUser!.id);
                                setState(() =>
                                    _providerProfile!['availability_status'] = newStatus);
                              },
                            ),
                            const SizedBox(height: 14),
                          ],

                          if (!hasActiveSubscription) ...[
                            _WarningBanner(
                              text: 'No active subscription — your profile is hidden.',
                              onTap: () => context.push('/provider/subscription'),
                            ),
                            const SizedBox(height: 14),
                          ],

                          if (_nextBooking != null)
                            _NextBookingCard(booking: _nextBooking!)
                          else
                            _NoBookingCard(),
                          const SizedBox(height: 14),

                          _StatsRow(
                            weeklyEarnings: _weeklyEarnings,
                            prevWeekEarnings: _prevWeekEarnings,
                            bookingsCount: _weeklyBookingsCount,
                            pendingCount: _pendingBookingsCount,
                            avgRating: _avgRating,
                            totalReviews: _totalReviews,
                          ),
                          const SizedBox(height: 20),

                          const Text('Quick Actions', style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                          )),
                          const SizedBox(height: 10),
                          _ProviderQuickActions(
                            pendingBookings: _pendingBookingsCount,
                            unreadMessages: _unreadMessages,
                            onShareProfile: () => _shareProfile(context),
                          ),
                          const SizedBox(height: 20),

                          if (_recentActivity.isNotEmpty) ...[
                            Row(
                              children: [
                                const Text('Recent Activity', style: TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                                )),
                                const Spacer(),
                                TextButton(
                                  onPressed: () => context.go('/provider/bookings'),
                                  style: TextButton.styleFrom(
                                    padding: EdgeInsets.zero,
                                    minimumSize: Size.zero,
                                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                  child: const Text('See all', style: TextStyle(fontSize: 13)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            _ActivityFeed(activities: _recentActivity),
                          ],

                          if (_providerProfile == null) ...[
                            const SizedBox(height: 8),
                            _SetupCard(onTap: () => context.push('/provider/profile/edit')),
                          ],
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _NextBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final clientName = booking['profiles']?['full_name'] ?? 'Client';
    final serviceName = booking['services']?['service_name'] ?? 'Service';
    final durationMin = booking['services']?['duration_minutes'];
    final bookingDate = booking['booking_date'] ?? '';
    final bookingTime = booking['booking_time'] ?? '';
    final bookingId = booking['id'];

    String timeDisplay = bookingTime;
    if (bookingTime.isNotEmpty) {
      try {
        final parts = bookingTime.split(':');
        final hour = int.parse(parts[0]);
        final minute = parts[1];
        final period = hour >= 12 ? 'PM' : 'AM';
        final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
        timeDisplay = '$displayHour:$minute $period';
      } catch (_) {}
    }

    String dateDisplay = bookingDate;
    String? countdown;
    if (bookingDate.isNotEmpty && bookingTime.isNotEmpty) {
      try {
        final date = DateTime.parse(bookingDate);
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final bookDay = DateTime(date.year, date.month, date.day);

        if (bookDay == today) {
          dateDisplay = 'Today';
        } else if (bookDay == tomorrow) {
          dateDisplay = 'Tomorrow';
        } else {
          final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
          dateDisplay = '${months[date.month - 1]} ${date.day}';
        }

        try {
          final timeParts = bookingTime.split(':');
          final bookingDt = DateTime(date.year, date.month, date.day,
              int.parse(timeParts[0]), int.parse(timeParts[1]));
          final diff = bookingDt.difference(now);
          if (diff.isNegative) {
            countdown = 'Now';
          } else if (diff.inMinutes < 60) {
            countdown = 'In ${diff.inMinutes} min';
          } else if (diff.inHours < 24) {
            countdown = 'In ${diff.inHours} hours';
          } else {
            countdown = 'In ${diff.inDays} days';
          }
        } catch (_) {}
      } catch (_) {}
    }

    final clientInitials = clientName.split(' ').map((w) => w.isNotEmpty ? w[0] : '').take(2).join().toUpperCase();

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1A2E), Color(0xFF2D2B55)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(color: const Color(0xFF1A1A2E).withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('NEXT BOOKING', style: TextStyle(
                  fontSize: 11, fontWeight: FontWeight.w700,
                  color: Colors.white.withValues(alpha: 0.6), letterSpacing: 1.2,
                )),
                const Spacer(),
                if (countdown != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(countdown, style: const TextStyle(
                      fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white,
                    )),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '$dateDisplay, $timeDisplay',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Text(clientInitials, style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white,
                  )),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(clientName, style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white,
                      )),
                      Text(
                        '$serviceName${durationMin != null ? ' · ${durationMin} min' : ''}',
                        style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/tracking/$bookingId'),
                      icon: const Icon(Icons.navigation_outlined, size: 16),
                      label: const Text('Navigate'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: FilledButton.icon(
                      onPressed: () => context.push('/chat/$bookingId'),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      label: const Text('Message'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _NoBookingCard extends StatelessWidget {
  const _NoBookingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.calendar_today_outlined, color: AppColors.info, size: 22),
          ),
          const SizedBox(height: 12),
          const Text('No Upcoming Bookings', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
          )),
          const SizedBox(height: 4),
          Text(
            'Your next booking will appear here',
            style: TextStyle(fontSize: 13, color: AppColors.textTertiary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _StatsRow extends StatelessWidget {
  final double weeklyEarnings;
  final double prevWeekEarnings;
  final int bookingsCount;
  final int pendingCount;
  final double avgRating;
  final int totalReviews;
  const _StatsRow({
    required this.weeklyEarnings, required this.prevWeekEarnings,
    required this.bookingsCount, required this.pendingCount,
    required this.avgRating, required this.totalReviews,
  });

  @override
  Widget build(BuildContext context) {
    String? earningsTrend;
    bool earningsUp = false;
    if (prevWeekEarnings > 0) {
      final pctChange = ((weeklyEarnings - prevWeekEarnings) / prevWeekEarnings * 100);
      earningsUp = pctChange >= 0;
      earningsTrend = '${earningsUp ? '↑' : '↓'} ${pctChange.abs().toStringAsFixed(0)}%';
    }

    return Row(
      children: [
        Expanded(child: _StatCard(
          topColor: AppColors.success,
          label: 'THIS WEEK',
          value: '\$${weeklyEarnings.toStringAsFixed(0)}',
          subtitle: earningsTrend,
          subtitleColor: earningsUp ? AppColors.success : AppColors.error,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          topColor: AppColors.info,
          label: 'BOOKINGS',
          value: '$bookingsCount',
          subtitle: pendingCount > 0 ? '$pendingCount pending' : null,
          subtitleColor: AppColors.warning,
        )),
        const SizedBox(width: 8),
        Expanded(child: _StatCard(
          topColor: const Color(0xFFD97706),
          label: 'RATING',
          value: avgRating > 0 ? avgRating.toStringAsFixed(1) : '—',
          subtitle: totalReviews > 0 ? '★ $totalReviews reviews' : null,
          subtitleColor: const Color(0xFFD97706),
        )),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final Color topColor;
  final String label;
  final String value;
  final String? subtitle;
  final Color? subtitleColor;
  const _StatCard({
    required this.topColor, required this.label, required this.value,
    this.subtitle, this.subtitleColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(height: 3, color: topColor),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(label, style: TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: AppColors.textTertiary, letterSpacing: 0.8,
                )),
                const SizedBox(height: 6),
                Text(value, style: const TextStyle(
                  fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                )),
                if (subtitle != null) ...[
                  const SizedBox(height: 3),
                  Text(subtitle!, style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w600,
                    color: subtitleColor ?? AppColors.textTertiary,
                  )),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AvailabilityToggle extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  const _AvailabilityToggle({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final isAvailable = status == 'available';
    final color = isAvailable ? AppColors.available : AppColors.offline;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              isAvailable ? Icons.wifi_tethering_rounded : Icons.wifi_tethering_off_rounded,
              color: color, size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isAvailable ? 'You\'re Available' : 'You\'re Offline',
                  style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 15),
                ),
                const SizedBox(height: 2),
                Text(
                  isAvailable ? 'Clients can find and book you' : 'You won\'t appear in search results',
                  style: TextStyle(fontSize: 12, color: AppColors.textTertiary),
                ),
              ],
            ),
          ),
          Transform.scale(
            scale: 1.1,
            child: Switch(
              value: isAvailable,
              onChanged: (val) => onChanged(val ? 'available' : 'offline'),
              activeColor: AppColors.available,
              activeTrackColor: AppColors.available.withValues(alpha: 0.3),
              inactiveThumbColor: AppColors.offline,
              inactiveTrackColor: AppColors.offline.withValues(alpha: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProviderQuickActions extends StatelessWidget {
  final int pendingBookings;
  final int unreadMessages;
  final VoidCallback onShareProfile;
  const _ProviderQuickActions({
    required this.pendingBookings,
    required this.unreadMessages,
    required this.onShareProfile,
  });

  @override
  Widget build(BuildContext context) {
    final uid = supabase.auth.currentUser!.id;

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _PrimaryActionTile(
              icon: Icons.calendar_month_rounded,
              label: 'Bookings',
              color: AppColors.info,
              badge: pendingBookings > 0 ? '$pendingBookings' : null,
              onTap: () => context.go('/provider/bookings'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _PrimaryActionTile(
              icon: Icons.account_balance_wallet_rounded,
              label: 'Earnings',
              color: AppColors.success,
              onTap: () => context.go('/earnings'),
            )),
            const SizedBox(width: 10),
            Expanded(child: _PrimaryActionTile(
              icon: Icons.chat_bubble_outline_rounded,
              label: 'Messages',
              color: AppColors.warning,
              badge: unreadMessages > 0 ? '$unreadMessages' : null,
              onTap: () => context.go('/provider/bookings'),
            )),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: _SecondaryActionTile(
              icon: Icons.person_outline,
              label: 'Profile',
              onTap: () => context.push('/provider/profile/edit'),
            )),
            const SizedBox(width: 8),
            Expanded(child: _SecondaryActionTile(
              icon: Icons.content_cut_rounded,
              label: 'Services',
              onTap: () => context.push('/provider/services'),
            )),
            const SizedBox(width: 8),
            Expanded(child: _SecondaryActionTile(
              icon: Icons.photo_library_outlined,
              label: 'Gallery',
              onTap: () => context.push('/provider/gallery'),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _SecondaryActionTile(
              icon: Icons.workspace_premium_rounded,
              label: 'Subscription',
              onTap: () => context.push('/provider/subscription'),
            )),
            const SizedBox(width: 8),
            Expanded(child: _SecondaryActionTile(
              icon: Icons.share_rounded,
              label: 'Share Profile',
              onTap: onShareProfile,
            )),
            const SizedBox(width: 8),
            Expanded(child: _SecondaryActionTile(
              icon: Icons.star_outline_rounded,
              label: 'Reviews',
              onTap: () => context.push('/provider/$uid/reviews'),
            )),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _SecondaryActionTile(
              icon: Icons.local_offer_outlined,
              label: 'Promos',
              onTap: () => context.push('/provider/promotions'),
            )),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()),
            const SizedBox(width: 8),
            const Expanded(child: SizedBox()),
          ],
        ),
      ],
    );
  }
}

class _PrimaryActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final String? badge;
  final VoidCallback onTap;
  const _PrimaryActionTile({required this.icon, required this.label, required this.color, this.badge, required this.onTap});

  @override
  State<_PrimaryActionTile> createState() => _PrimaryActionTileState();
}

class _PrimaryActionTileState extends State<_PrimaryActionTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            color: _hovering ? widget.color.withValues(alpha: 0.06) : Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: _hovering ? widget.color.withValues(alpha: 0.3) : Colors.grey.shade200,
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: widget.color.withValues(alpha: 0.1), blurRadius: 12, offset: const Offset(0, 4))]
                : [],
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Center(
                child: Column(
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: _hovering ? 50 : 46,
                      height: _hovering ? 50 : 46,
                      decoration: BoxDecoration(
                        color: widget.color.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(widget.icon, color: widget.color, size: _hovering ? 26 : 24),
                    ),
                    const SizedBox(height: 10),
                    Text(widget.label, style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600,
                      color: _hovering ? widget.color : AppColors.textPrimary,
                    )),
                  ],
                ),
              ),
              if (widget.badge != null)
                Positioned(
                  top: -4, right: 16,
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(color: AppColors.error, shape: BoxShape.circle),
                    child: Center(
                      child: Text(widget.badge!, style: const TextStyle(
                        color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700,
                      )),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryActionTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SecondaryActionTile({required this.icon, required this.label, required this.onTap});

  @override
  State<_SecondaryActionTile> createState() => _SecondaryActionTileState();
}

class _SecondaryActionTileState extends State<_SecondaryActionTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _hovering ? Colors.grey.shade50 : Colors.white,
            borderRadius: AppRadius.mdAll,
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: AppColors.textSecondary, size: 18),
              ),
              const SizedBox(height: 6),
              Text(widget.label, style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w500,
                color: _hovering ? AppColors.textPrimary : AppColors.textSecondary,
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityFeed extends StatelessWidget {
  final List<Map<String, dynamic>> activities;
  const _ActivityFeed({required this.activities});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: ListView.separated(
        physics: const NeverScrollableScrollPhysics(),
        shrinkWrap: true,
        padding: EdgeInsets.zero,
        itemCount: activities.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100, indent: 60),
        itemBuilder: (context, index) => _ActivityItem(activity: activities[index]),
      ),
    );
  }
}

class _ActivityItem extends StatelessWidget {
  final Map<String, dynamic> activity;
  const _ActivityItem({required this.activity});

  @override
  Widget build(BuildContext context) {
    final type = activity['type'] as String;
    final data = activity['data'] as Map<String, dynamic>;
    final createdAt = activity['created_at'] as String? ?? '';

    IconData icon;
    Color color;
    String title;
    String subtitle;
    Widget? trailing;

    if (type == 'review') {
      icon = Icons.star_rounded;
      color = const Color(0xFFD97706);
      final rating = data['rating'] ?? 0;
      title = 'New $rating-star review';
      final comment = data['comment'] as String? ?? '';
      subtitle = comment.isNotEmpty
          ? '"${comment.length > 50 ? '${comment.substring(0, 50)}…' : comment}"'
          : 'No comment';
    } else if (type == 'payment') {
      icon = Icons.payments_outlined;
      color = AppColors.success;
      final amount = (data['amount'] as num?)?.toDouble() ?? 0;
      final clientName = data['bookings']?['profiles']?['full_name'] ?? '';
      final serviceName = data['bookings']?['services']?['service_name'] ?? 'Service';
      title = 'Payment received';
      subtitle = '\$${amount.toStringAsFixed(0)} for $serviceName${clientName.isNotEmpty ? ' from $clientName' : ''}';
      trailing = Text('+\$${amount.toStringAsFixed(0)}', style: TextStyle(
        fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success,
      ));
    } else {
      final bookingStatus = data['status'] ?? 'pending';
      icon = _bookingIcon(bookingStatus);
      color = StatusColors.foreground(bookingStatus);
      final clientName = data['profiles']?['full_name'] ?? 'Client';
      final serviceName = data['services']?['service_name'] ?? 'Service';
      title = '$clientName — $serviceName';
      subtitle = StatusColors.label(bookingStatus);
    }

    String timeAgo = '';
    if (createdAt.isNotEmpty) {
      try {
        final dt = DateTime.parse(createdAt);
        final diff = DateTime.now().difference(dt);
        if (diff.inMinutes < 60) {
          timeAgo = '${diff.inMinutes}m ago';
        } else if (diff.inHours < 24) {
          timeAgo = '${diff.inHours}h ago';
        } else {
          timeAgo = '${diff.inDays}d ago';
        }
      } catch (_) {}
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary), maxLines: 1, overflow: TextOverflow.ellipsis),
                if (timeAgo.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(timeAgo, style: TextStyle(fontSize: 11, color: AppColors.textTertiary.withValues(alpha: 0.7))),
                  ),
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }

  IconData _bookingIcon(String status) {
    switch (status) {
      case 'confirmed': return Icons.check_circle_outline_rounded;
      case 'en_route': return Icons.directions_walk_rounded;
      case 'arrived': return Icons.location_on_outlined;
      case 'in_progress': return Icons.auto_fix_high_rounded;
      case 'completed': return Icons.task_alt_rounded;
      case 'cancelled': return Icons.cancel_outlined;
      default: return Icons.schedule_rounded;
    }
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;
  final VoidCallback onTap;
  const _WarningBanner({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.06),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(Icons.warning_amber_rounded, color: AppColors.error, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(color: AppColors.error, fontSize: 12, fontWeight: FontWeight.w500))),
          Icon(Icons.chevron_right, color: AppColors.error, size: 18),
        ]),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  final VoidCallback onTap;
  const _SetupCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.info.withValues(alpha: 0.06),
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.info.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Icon(Icons.rocket_launch_rounded, size: 36, color: AppColors.info),
          const SizedBox(height: 10),
          const Text('Complete your provider profile to appear in search results.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          FilledButton(onPressed: onTap, child: const Text('Set Up Profile')),
        ],
      ),
    );
  }
}

class _VerificationBanner extends StatelessWidget {
  final String? status;
  final VoidCallback onTap;
  const _VerificationBanner({required this.status, required this.onTap});

  @override
  Widget build(BuildContext context) {
    Color bannerColor;
    String message;
    IconData icon;
    switch (status) {
      case 'pending':
        bannerColor = AppColors.warning;
        message = 'Verification under review. Tap to check status.';
        icon = Icons.hourglass_top_rounded; break;
      case 'rejected':
        bannerColor = AppColors.error;
        message = 'Verification rejected. Tap to re-submit.';
        icon = Icons.cancel_outlined; break;
      default:
        bannerColor = AppColors.info;
        message = 'Verify your identity to unlock all features.';
        icon = Icons.verified_user_outlined;
    }
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bannerColor.withValues(alpha: 0.06),
          borderRadius: AppRadius.mdAll,
          border: Border.all(color: bannerColor.withValues(alpha: 0.2)),
        ),
        child: Row(children: [
          Icon(icon, color: bannerColor, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: bannerColor, fontWeight: FontWeight.w500))),
          Icon(Icons.chevron_right, color: bannerColor, size: 18),
        ]),
      ),
    );
  }
}
