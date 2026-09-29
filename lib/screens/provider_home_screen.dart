import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart';

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
  int _totalReviews = 0;
  double _avgRating = 0;
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _todayBookings = [];
  List<Map<String, dynamic>> _requests = [];
  Map<String, dynamic>? _plan;

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
          child: const Icon(TablerIcons.rosette_discount_check,
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
    int totalReviews = 0;
    double avgRating = 0;
    int unreadNotifs = 0;

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
      nextBooking = await supabase
          .from('bookings')
          .select('*, services(service_name, duration_minutes), profiles!bookings_client_id_fkey(full_name)')
          .eq('provider_id', userId)
          .eq('status', 'confirmed')
          .gte('booking_time', DateTime.now().subtract(const Duration(hours: 3)).toUtc().toIso8601String())
          .order('booking_time', ascending: true)
          .limit(1)
          .maybeSingle();
    } catch (_) {}

    try {
      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final twoWeeksAgo = now.subtract(const Duration(days: 14)).toUtc().toIso8601String();

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
      final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toUtc().toIso8601String();
      final bookings = await supabase
          .from('bookings')
          .select('id, status')
          .eq('provider_id', userId)
          .gte('created_at', weekAgo);
      weeklyBookingsCount = (bookings as List).length;
      pendingBookingsCount = bookings.where((b) => b['status'] == 'pending' || b['status'] == 'confirmed').length;
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
      unreadNotifs = await NotificationService.unreadCount(userId);
    } catch (_) {}

    Map<String, dynamic>? plan;
    try {
      plan = Map<String, dynamic>.from(await supabase.rpc('my_plan') as Map);
    } catch (_) {}

    var todayBookings = <Map<String, dynamic>>[];
    var requests = <Map<String, dynamic>>[];
    try {
      final n = DateTime.now();
      final start = DateTime(n.year, n.month, n.day);
      const sel = 'id, booking_time, status, total_price, payment_status, source, walkin_name, walkin_phone, client_id, '
          'services(service_name, duration_minutes), service_tiers(name, duration_minutes), '
          'client:profiles!bookings_client_id_fkey(full_name, phone)';
      final results = await Future.wait<dynamic>([
        supabase
            .from('bookings')
            .select(sel)
            .eq('provider_id', userId)
            .inFilter('status', ['confirmed', 'completed'])
            .gte('booking_time', start.toUtc().toIso8601String())
            .lt('booking_time', start.add(const Duration(days: 1)).toUtc().toIso8601String())
            .order('booking_time', ascending: true),
        supabase
            .from('bookings')
            .select(sel)
            .eq('provider_id', userId)
            .eq('status', 'pending')
            .gte('booking_time', n.toUtc().toIso8601String())
            .order('booking_time', ascending: true)
            .limit(10),
      ]);
      todayBookings = List<Map<String, dynamic>>.from(results[0] as List);
      requests = List<Map<String, dynamic>>.from(results[1] as List);
      for (final b in [...todayBookings, ...requests]) {
        fillWalkin(b, 'client');
      }
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
        _totalReviews = totalReviews;
        _avgRating = avgRating;
        _unreadNotifications = unreadNotifs;
        _todayBookings = todayBookings;
        _requests = requests;
        _plan = plan;
        _loading = false;
      });
      _animCtrl.forward();
    }
  }

  Future<void> _respond(Map<String, dynamic> b, bool accept) async {
    try {
      await supabase.from('bookings').update({
        'status': accept ? 'confirmed' : 'cancelled',
        if (!accept) 'cancel_reason': 'Declined by stylist',
      }).eq('id', b['id']);
      NotificationService.send(
        userId: b['client_id'],
        type: 'booking_status',
        title: accept ? 'Booking confirmed' : 'Booking declined',
        body: accept
            ? 'Your ${b['services']?['service_name'] ?? 'booking'} is confirmed.'
            : 'Your stylist can\'t take this booking. Try another time or stylist.',
        referenceId: b['id'],
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(accept ? 'Booking confirmed' : 'Booking declined')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not update: $e'), backgroundColor: AppColors.error));
      }
    }
    _loadData();
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

    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const mo = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final now = DateTime.now();
    final dateLabel = '${wd[now.weekday - 1]} ${now.day} ${mo[now.month - 1]}';
    final availability = (_providerProfile?['availability_status'] ?? 'offline').toString();

    return Scaffold(
      bottomNavigationBar: isVerified
          ? Container(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => context.go('/provider/calendar'),
                    icon: const Icon(TablerIcons.calendar_event, size: 18),
                    label: const Text('Calendar'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll)),
                    onPressed: () => context.push('/provider/add-booking').then((_) => _loadData()),
                    icon: const Icon(TablerIcons.plus, size: 18),
                    label: const Text('Add walk-in'),
                  ),
                ),
              ]),
            )
          : null,
      body: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: ForestHeader(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(children: [
                    Row(children: [
                      GestureDetector(
                        onTap: () => context.go('/provider/profile'),
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(color: AppColors.gold, shape: BoxShape.circle),
                          child: _profile?['avatar_url'] != null
                              ? PersonAvatar(name: name, url: _profile?['avatar_url'], size: 44)
                              : Container(
                                  width: 44,
                                  height: 44,
                                  decoration: const BoxDecoration(color: AppColors.pine, shape: BoxShape.circle),
                                  alignment: Alignment.center,
                                  child: Text(
                                    name.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).take(2).map((w) => w[0]).join().toUpperCase(),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w800),
                              overflow: TextOverflow.ellipsis),
                          const SizedBox(height: 2),
                          Row(children: [
                            if (_avgRating > 0) ...[
                              const Icon(TablerIcons.star_filled, color: AppColors.gold, size: 15),
                              const SizedBox(width: 3),
                              Text('${_avgRating.toStringAsFixed(1)} · ',
                                  style: const TextStyle(color: Color(0xFFD5E2DC), fontSize: 14)),
                            ],
                            Text(dateLabel, style: const TextStyle(color: Color(0xFFD5E2DC), fontSize: 14)),
                          ]),
                        ]),
                      ),
                      if (_isAdmin)
                        IconButton(
                          tooltip: 'Admin',
                          icon: const Icon(TablerIcons.shield_lock, color: Colors.white),
                          onPressed: () => context.push('/admin/dashboard'),
                        ),
                      IconButton(
                        tooltip: 'Notifications',
                        onPressed: () => context.push('/notifications'),
                        icon: Badge(
                          isLabelVisible: _unreadNotifications > 0,
                          backgroundColor: AppColors.gold,
                          textColor: AppColors.textPrimary,
                          label: Text(_unreadNotifications > 9 ? '9+' : '$_unreadNotifications'),
                          child: const Icon(TablerIcons.bell, color: Colors.white),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Menu',
                        icon: const Icon(TablerIcons.menu_2, color: Colors.white),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
                        onSelected: (v) {
                          if (v == 'settings') context.push('/account/settings');
                          if (v == 'business') context.push('/provider/settings');
                          if (v == 'signout') _signOut();
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'business', child: Text('Business settings')),
                          PopupMenuItem(value: 'settings', child: Text('Account settings')),
                          PopupMenuItem(value: 'signout', child: Text('Sign out')),
                        ],
                      ),
                    ]),
                    if (isVerified && _providerProfile != null) ...[
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _AvailabilitySegments(
                          status: availability,
                          onChanged: (newStatus) async {
                            setState(() => _providerProfile!['availability_status'] = newStatus);
                            await supabase
                                .from('provider_profiles')
                                .update({'availability_status': newStatus})
                                .eq('provider_id', supabase.auth.currentUser!.id);
                          },
                        ),
                      ),
                    ],
                  ]),
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
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
                          if (!hasActiveSubscription) ...[
                            _PlanBanner(
                              used: (_plan?['free_used'] as num?)?.toInt() ?? 0,
                              limit: (_plan?['free_limit'] as num?)?.toInt() ?? 5,
                              onTap: () => context.push('/provider/subscription'),
                            ),
                            const SizedBox(height: 14),
                          ],

                          if (_requests.isNotEmpty) ...[
                            _SectionTitle('Needs your answer', count: _requests.length),
                            for (final b in _requests)
                              _RequestCard(
                                booking: b,
                                onTap: () => context.push('/booking/${b['id']}').then((_) => _loadData()),
                                onAccept: () => _respond(b, true),
                                onDecline: () => _respond(b, false),
                              ),
                            const SizedBox(height: 16),
                          ],

                          _SectionTitle(
                            'Today',
                            trailing: _todayBookings.isEmpty
                                ? null
                                : '${_todayBookings.length} ${_todayBookings.length == 1 ? 'booking' : 'bookings'} · '
                                    '${money(_todayBookings.fold<num>(0, (s, b) => s + ((b['total_price'] as num?) ?? 0)))}',
                          ),
                          if (_todayBookings.isEmpty) ...[
                            if (_nextBooking != null)
                              _NextBookingCard(booking: _nextBooking!)
                            else
                              _NoBookingCard(),
                          ] else
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: AppRadius.mdAll,
                                border: Border.all(color: AppColors.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Column(children: [
                                for (var k = 0; k < _todayBookings.length; k++) ...[
                                  if (k > 0) const Divider(height: 1),
                                  _TodayRow(
                                    booking: _todayBookings[k],
                                    onTap: () => context.push('/booking/${_todayBookings[k]['id']}').then((_) => _loadData()),
                                  ),
                                ],
                              ]),
                            ),
                          const SizedBox(height: 20),

                          _StatsRow(
                            weeklyEarnings: _weeklyEarnings,
                            prevWeekEarnings: _prevWeekEarnings,
                            bookingsCount: _weeklyBookingsCount,
                            pendingCount: _pendingBookingsCount,
                            avgRating: _avgRating,
                            totalReviews: _totalReviews,
                          ),
                          const SizedBox(height: 20),

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
    final bookingId = booking['id'];
    final bookingDt =
        DateTime.tryParse(booking['booking_time'] ?? '')?.toLocal();

    String timeDisplay = '';
    String dateDisplay = '';
    String? countdown;
    if (bookingDt != null) {
      final hour = bookingDt.hour;
      final minute = bookingDt.minute.toString().padLeft(2, '0');
      final period = hour >= 12 ? 'PM' : 'AM';
      final displayHour = hour > 12 ? hour - 12 : (hour == 0 ? 12 : hour);
      timeDisplay = '$displayHour:$minute $period';

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final tomorrow = today.add(const Duration(days: 1));
      final bookDay = DateTime(bookingDt.year, bookingDt.month, bookingDt.day);
      if (bookDay == today) {
        dateDisplay = 'Today';
      } else if (bookDay == tomorrow) {
        dateDisplay = 'Tomorrow';
      } else {
        const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        dateDisplay = '${months[bookingDt.month - 1]} ${bookingDt.day}';
      }

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
                      onPressed: () => context.push('/booking/$bookingId'),
                      icon: const Icon(TablerIcons.receipt, size: 16),
                      label: const Text('Details'),
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
                      icon: const Icon(TablerIcons.message_circle, size: 16),
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
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: AppColors.info.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(TablerIcons.calendar, color: AppColors.info, size: 22),
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
        border: Border.all(color: AppColors.border),
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
          Icon(TablerIcons.rocket, size: 36, color: AppColors.info),
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
        icon = TablerIcons.hourglass_high; break;
      case 'rejected':
        bannerColor = AppColors.error;
        message = 'Verification rejected. Tap to re-submit.';
        icon = TablerIcons.circle_x; break;
      default:
        bannerColor = AppColors.info;
        message = 'Verify your identity to unlock all features.';
        icon = TablerIcons.shield_check;
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
          Icon(TablerIcons.chevron_right, color: bannerColor, size: 18),
        ]),
      ),
    );
  }
}


class _SectionTitle extends StatelessWidget {
  final String text;
  final int? count;
  final String? trailing;
  const _SectionTitle(this.text, {this.count, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Text(text, style: Theme.of(context).textTheme.titleLarge),
        if (count != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: AppColors.warningSoft, borderRadius: AppRadius.xsAll),
            child: Text('$count', style: const TextStyle(color: AppColors.warningText, fontWeight: FontWeight.w800, fontSize: 13)),
          ),
        ],
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
      ]),
    );
  }
}

class _AvailabilitySegments extends StatelessWidget {
  final String status;
  final ValueChanged<String> onChanged;
  const _AvailabilitySegments({required this.status, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    const opts = [('available', 'Available'), ('busy', 'Busy'), ('offline', 'Offline')];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: AppColors.pine, borderRadius: AppRadius.mdAll),
      child: Row(children: [
        for (final o in opts)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(o.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: status == o.$1 ? Colors.white : Colors.transparent,
                  borderRadius: AppRadius.smAll,
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (status == o.$1) ...[
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: o.$1 == 'available'
                            ? AppColors.available
                            : o.$1 == 'busy'
                                ? AppColors.warning
                                : AppColors.offline,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(o.$2,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: status == o.$1 ? FontWeight.w800 : FontWeight.w600,
                        color: status == o.$1 ? AppColors.primary : const Color(0xFFD5E2DC),
                      )),
                ]),
              ),
            ),
          ),
      ]),
    );
  }
}

class _PlanBanner extends StatelessWidget {
  final int used;
  final int limit;
  final VoidCallback onTap;
  const _PlanBanner({required this.used, required this.limit, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.cream,
      borderRadius: AppRadius.mdAll,
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text.rich(TextSpan(children: [
                  const TextSpan(text: 'Free plan', style: TextStyle(fontWeight: FontWeight.w800)),
                  TextSpan(text: ' · $used of $limit app bookings'),
                ]), style: const TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: limit == 0 ? 0 : (used / limit).clamp(0, 1).toDouble(),
                    minHeight: 4,
                    backgroundColor: const Color(0xFFE6D8B8),
                    color: AppColors.primary,
                  ),
                ),
              ]),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              child: Text('Go Pro', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.primary)),
            ),
          ]),
        ),
      ),
    );
  }
}

class _TodayRow extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onTap;
  const _TodayRow({required this.booking, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = DateTime.parse(b['booking_time']).toLocal();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final done = b['status'] == 'completed';
    final paid = b['payment_status'] == 'paid';
    final service = b['service_tiers']?['name'] != null
        ? '${b['services']?['service_name']} · ${b['service_tiers']['name']}'
        : (b['services']?['service_name'] ?? 'Service');
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        child: Row(children: [
          SizedBox(
            width: 60,
            child: Text(hm,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: done ? AppColors.textSecondary : AppColors.textPrimary,
                )),
          ),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(b['client']?['full_name'] ?? 'Client',
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              Text(service,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(money((b['total_price'] as num?) ?? 0), style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
            if (paid)
              const Padding(padding: EdgeInsets.only(top: 4), child: Pill(label: 'Paid', color: AppColors.success))
            else if (isManualBooking(b))
              const Padding(padding: EdgeInsets.only(top: 4), child: Pill(label: 'Walk-in', color: Color(0xFF3E4A45)))
            else if (done)
              const Padding(padding: EdgeInsets.only(top: 4), child: Pill(label: 'Done', color: AppColors.success)),
          ]),
        ]),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  final VoidCallback onTap;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _RequestCard({required this.booking, required this.onTap, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = DateTime.parse(b['booking_time']).toLocal();
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final when = '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}, '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final service = [b['services']?['service_name'], b['service_tiers']?['name']].where((x) => x != null).join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Container(width: 4, color: AppColors.warning),
          Expanded(
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      child: Text(b['client']?['full_name'] ?? 'Client',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                    ),
                    Text(money((b['total_price'] as num?) ?? 0),
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  ]),
                  const SizedBox(height: 2),
                  Text('$service · $when', style: Theme.of(context).textTheme.bodySmall),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: OutlinedButton(onPressed: onDecline, child: const Text('Decline'))),
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48), shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll)),
                        onPressed: onAccept,
                        child: const Text('Accept'),
                      ),
                    ),
                  ]),
                ]),
              ),
            ),
          ),
        ]),
      ),
    );
  }
}
