import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../supabase_client.dart';
import '../services/earnings_service.dart';
import '../services/referral_service.dart';
import '../services/notification_service.dart';
import '../services/push_service.dart';
import '../glass.dart';
import '../theme.dart';
import '../widgets/ui.dart';
import '../utils/booking_helpers.dart';
import '../utils/pay_methods.dart';
import '../utils/feel.dart';
import '../widgets/booking_bits.dart';

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
  /// Earnings for each of the last 7 days, oldest first (for the bar chart).
  List<double> _daily = List.filled(7, 0);
  int _galleryCount = 0;
  /// Requests answered on screen but not sent yet (5 seconds to undo).
  final Set<String> _deciding = {};
  /// Bookings marked paid on screen but not saved yet (5 seconds to undo).
  final Set<String> _paying = {};

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    WidgetsBinding.instance.addObserver(this);
    _loadData();
    _subscribeRealtime();
    applyPendingReferral();
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
          child: Icon(TablerIcons.rosette_discount_check,
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
      final earned = await EarningsService.load();
      weeklyEarnings = earned.between(now.subtract(const Duration(days: 7)), now.add(const Duration(days: 1)));
      final today = DateTime(now.year, now.month, now.day);
      _daily = [
        for (var i = 6; i >= 0; i--)
          earned.between(today.subtract(Duration(days: i)), today.subtract(Duration(days: i - 1))),
      ];
      prevWeekEarnings = earned.between(now.subtract(const Duration(days: 14)), now.subtract(const Duration(days: 7)));
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

    try {
      final g = await supabase.from('hairstyle_gallery').select('id').eq('provider_id', userId).limit(12);
      _galleryCount = (g as List).length;
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
      const sel = 'deposit_amount, deposit_paid, id, booking_time, status, total_price, payment_status, payment_method, at_studio, source, walkin_name, walkin_phone, client_id, '
          'services(service_name, duration_minutes), service_tiers(name, duration_minutes), '
          'client:profiles!bookings_client_id_fkey(full_name, phone, avatar_url)';
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

  Future<void> _respond(Map<String, dynamic> b, bool accept, {bool quiet = false}) async {
    final paid = paidSoFar(b);
    if (!accept && paid > 0) {
      if (!await confirmPaidCancel(context, b,
          byPro: true, otherName: (b['client'] as Map?)?['full_name'] ?? b['walkin_name'])) {
        return;
      }
    }
    try {
      await supabase.from('bookings').update({
        'status': accept ? 'confirmed' : 'cancelled',
        if (!accept) 'cancel_reason': 'Declined by pro',
      }).eq('id', b['id']);
      NotificationService.send(
        userId: b['client_id'],
        type: 'booking_status',
        title: accept ? 'Booking confirmed' : 'Booking declined',
        body: accept
            ? 'Your ${b['services']?['service_name'] ?? 'booking'} is confirmed.'
            : 'Your pro can\'t take this booking. Try another time or pro.'
                '${paid > 0 ? ' They\'ll refund the ${money(paid)} you paid.' : ''}',
        referenceId: b['id'],
      );
      if (mounted && !quiet) {
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

  /// Swipe or button: hide the request, give 5 seconds to undo, then send.
  Future<void> _decide(Map<String, dynamic> b, bool accept) async {
    final id = b['id'] as String;
    if (_deciding.contains(id)) return;
    if (!accept && paidSoFar(b) > 0) {
      // Money already paid: ask first, no undo needed after that.
      return _respond(b, false);
    }
    accept ? Haptics.firm() : Haptics.warn();
    setState(() => _deciding.add(id));
    final who = (b['client'] as Map?)?['full_name'] ?? b['walkin_name'] ?? 'the client';
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(SnackBar(
          content: Text(accept ? 'Accepted $who' : 'Declined $who'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ))
        .closed;
    if (reason == SnackBarClosedReason.action) {
      Haptics.light();
      if (mounted) setState(() => _deciding.remove(id));
      return;
    }
    await _respond(b, accept, quiet: true);
    _deciding.remove(id);
  }

  /// Mark a booking paid. The week's total counts up straight away; it is
  /// saved after 5 seconds unless undone.
  Future<void> _markPaid(Map<String, dynamic> b) async {
    final id = b['id'] as String;
    if (_paying.contains(id)) return;
    final amount = ((b['total_price'] as num?) ?? 0).toDouble() - paidSoFar(b);
    Haptics.firm();
    setState(() {
      _paying.add(id);
      _weeklyEarnings += amount;
      _daily[6] += amount;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final reason = await messenger
        .showSnackBar(SnackBar(
          content: Text('Marked paid · ${money(amount)}'),
          duration: const Duration(seconds: 5),
          action: SnackBarAction(label: 'Undo', onPressed: () {}),
        ))
        .closed;
    if (reason == SnackBarClosedReason.action) {
      Haptics.light();
      if (mounted) {
        setState(() {
          _paying.remove(id);
          _weeklyEarnings -= amount;
          _daily[6] -= amount;
        });
      }
      return;
    }
    try {
      await supabase.from('bookings').update({'payment_status': 'paid'}).eq('id', id);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e'), backgroundColor: AppColors.error));
    }
    _paying.remove(id);
    _loadData();
  }

  Future<void> _signOut() async {
    await supabase.auth.signOut();
    if (mounted) context.go('/login');
  }

  /// Gentle tips that help pros get more bookings.
  List<Widget> _nudges() {
    final pp = _providerProfile;
    if (pp == null) return const [];
    final wa = (pp['whatsapp_number'] ?? '').toString().trim().isNotEmpty &&
        ['whatsapp', 'both'].contains(pp['preferred_contact']);
    final tips = <Widget>[
      if (!wa)
        _Nudge(
          icon: TablerIcons.brand_whatsapp,
          title: 'Let clients WhatsApp you',
          message: 'Pros with WhatsApp on get more bookings. Your number stays hidden until you turn it on.',
          action: 'Turn on',
          onTap: () => context.push('/provider/settings').then((_) => _loadData()),
        ),
      if ((_profile?['avatar_url'] ?? '').toString().isEmpty)
        _Nudge(
          icon: TablerIcons.camera,
          title: 'Add a profile photo',
          message: 'Clients book faces they can see. Profiles with photos get more bookings.',
          action: 'Add',
          onTap: () => context.push('/provider/profile/edit').then((_) => _loadData()),
        ),
      if (_galleryCount < 6)
        _Nudge(
          icon: TablerIcons.photo,
          title: _galleryCount == 0 ? 'Show your work' : 'Add ${6 - _galleryCount} more work photos',
          message: 'Profiles with 6 or more photos get twice the views.',
          action: 'Add',
          onTap: () => context.push('/provider/gallery').then((_) => _loadData()),
        ),
    ];
    if (tips.isEmpty) return const [];
    return [
      const _SectionTitle('Grow your bookings'),
      for (final t in tips) Padding(padding: const EdgeInsets.only(bottom: 8), child: t),
      const SizedBox(height: 12),
    ];
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
                child: CircularProgressIndicator.adaptive(strokeWidth: 3, valueColor: AlwaysStoppedAnimation(AppColors.primary))),
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
              decoration: BoxDecoration(
                color: AppColors.card,
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
                  constraints: const BoxConstraints(maxWidth: kPageMaxWidth),
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
                          Text('${now.hour < 12 ? 'Good morning' : now.hour < 17 ? 'Good afternoon' : 'Good evening'} · $dateLabel',
                              style: const TextStyle(color: Color(0xFFBDB3A4), fontSize: 13)),
                          const SizedBox(height: 2),
                          Text(name,
                              style: const TextStyle(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w700),
                              overflow: TextOverflow.ellipsis),
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
                  constraints: const BoxConstraints(maxWidth: kPageMaxWidth),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + tabBarSpace(context)),
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

                        if (_providerProfile != null &&
                            (_providerProfile!['city_id'] == null ||
                                (_providerProfile!['area'] ?? '').toString().trim().isEmpty)) ...[
                          SoftBanner(
                            icon: TablerIcons.map_pin_exclamation,
                            color: AppColors.error,
                            title: 'Set where you work',
                            message: 'Clients can\'t find or book you until you add your city and area.',
                            actionLabel: 'Set now',
                            onTap: () => context.push('/provider/location').then((_) => _loadData()),
                          ),
                          const SizedBox(height: 16),
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

                          _EarningsCard(
                            week: _weeklyEarnings,
                            lastWeek: _prevWeekEarnings,
                            daily: _daily,
                            bookings: _weeklyBookingsCount,
                            pending: _pendingBookingsCount,
                            rating: _avgRating,
                            reviews: _totalReviews,
                          ),
                          const SizedBox(height: 18),

                          if (_requests.any((r) => !_deciding.contains(r['id']))) ...[
                            _SectionTitle('Needs your answer',
                                count: _requests.where((r) => !_deciding.contains(r['id'])).length),
                            AdaptiveGrid(minTileWidth: 380, children: [
                              for (final b in _requests.where((r) => !_deciding.contains(r['id'])))
                                Padding(
                                  key: ValueKey(b['id']),
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: SwipeToDecide(
                                    onAccept: () => _decide(b, true),
                                    onDecline: () => _decide(b, false),
                                    child: _RequestCard(
                                      booking: b,
                                      onTap: () => context.push('/booking/${b['id']}').then((_) => _loadData()),
                                      onAccept: () => _decide(b, true),
                                      onDecline: () => _decide(b, false),
                                    ),
                                  ),
                                ),
                            ]),
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Center(
                                child: Text('Swipe right to accept, left to decline',
                                    style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                              ),
                            ),
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
                            for (final b in _todayBookings)
                              _TodayRow(
                                key: ValueKey(b['id']),
                                booking: b,
                                paying: _paying.contains(b['id']),
                                onMarkPaid: () => _markPaid(b),
                                onTap: () => context.push('/booking/${b['id']}').then((_) => _loadData()),
                              ),
                          const SizedBox(height: 18),

                          ..._nudges(),

                          if (_providerProfile == null) ...[
                            const SizedBox(height: 8),
                            _SetupCard(onTap: () => context.push('/provider/profile/edit')),
                          ] else if (payMethodsOf(_providerProfile, includeCash: false).isEmpty) ...[
                            SoftBanner(
                              icon: TablerIcons.device_mobile,
                              color: AppColors.primary,
                              title: 'Add EcoCash so clients can pay you',
                              message: 'Right now clients can only choose cash. Add your EcoCash number, '
                                  'InnBucks or bank details to take deposits and payments before the day.',
                              actionLabel: 'Add',
                              onTap: () => context.push('/provider/settings').then((_) => _loadData()),
                            ),
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
      decoration: Glass.hero(),
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
                    color: Colors.white.withValues(alpha: 0.16),
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
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
                        backgroundColor: Colors.transparent,
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
                        foregroundColor: AppColors.onPrimary,
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
        color: AppColors.card,
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
          Text('No Upcoming Bookings', style: TextStyle(
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

/// This week's earnings (counting up), a 7-day bar chart, bookings and rating.
class _EarningsCard extends StatelessWidget {
  final double week;
  final double lastWeek;
  final List<double> daily;
  final int bookings;
  final int pending;
  final double rating;
  final int reviews;
  const _EarningsCard({
    required this.week,
    required this.lastWeek,
    required this.daily,
    required this.bookings,
    required this.pending,
    required this.rating,
    required this.reviews,
  });

  @override
  Widget build(BuildContext context) {
    final diff = week - lastWeek;
    final top = daily.fold<double>(0, (m, v) => v > m ? v : m);
    final shadow = AppColors.isDark ? null : AppShadows.lifted;
    Widget small(String label, String value, {String? sub, VoidCallback? onTap}) => Expanded(
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(label, style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary)),
                  const SizedBox(height: 2),
                  Text(value, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  if (sub != null) Text(sub, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.goldText)),
                ]),
              ),
            ),
          ),
        );
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
          flex: 14,
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(22),
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => context.push('/earnings'),
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(22), boxShadow: shadow),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('This week', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  CountUpMoney(
                    value: week,
                    style: TextStyle(
                        fontFamily: AppTheme.displayFamily,
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.6,
                        color: AppColors.textPrimary),
                  ),
                  if (lastWeek > 0 || week > 0)
                    Text(
                      diff >= 0 ? '▲ ${money(diff)} more than last week' : '▼ ${money(-diff)} less than last week',
                      style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600, color: diff >= 0 ? AppColors.success : AppColors.errorText),
                    ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 30,
                    child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      for (var i = 0; i < daily.length; i++) ...[
                        if (i > 0) const SizedBox(width: 4),
                        Expanded(
                          child: AnimatedContainer(
                            duration: Motion.of(context, Motion.slow),
                            height: top <= 0 ? 4 : 4 + 26 * (daily[i] / top),
                            decoration: BoxDecoration(
                              color: i == daily.length - 1 ? AppColors.gold : AppColors.surfaceMuted,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                        ),
                      ],
                    ]),
                  ),
                ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          flex: 10,
          child: Column(children: [
            small('Bookings', '$bookings', sub: pending > 0 ? '$pending to come' : null,
                onTap: () => context.push('/provider/bookings')),
            const SizedBox(height: 10),
            small('Rating', rating > 0 ? '★ ${rating.toStringAsFixed(1)}' : 'New',
                sub: reviews > 0 ? '$reviews reviews' : null, onTap: () => context.push('/provider/${supabase.auth.currentUser!.id}/reviews')),
          ]),
        ),
      ]),
    );
  }
}

class _Nudge extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String action;
  final VoidCallback onTap;
  const _Nudge({required this.icon, required this.title, required this.message, required this.action, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primarySoft,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(color: AppColors.gold, borderRadius: BorderRadius.circular(14)),
              child: Icon(icon, color: const Color(0xFF17130E), size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text(message, style: TextStyle(fontSize: 12.5, height: 1.35, color: AppColors.textSecondary)),
              ]),
            ),
            const SizedBox(width: 10),
            Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              decoration: BoxDecoration(color: AppColors.primary, borderRadius: AppRadius.pill),
              child: Text(action, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.onPrimary)),
            ),
          ]),
        ),
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
          Text('Complete your provider profile to appear in search results.',
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
            decoration: BoxDecoration(color: AppColors.gold, borderRadius: AppRadius.pill),
            child: Text('$count', style: const TextStyle(color: Color(0xFF17130E), fontWeight: FontWeight.w700, fontSize: 12)),
          ),
        ],
        const Spacer(),
        if (trailing != null)
          Text(trailing!, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary)),
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
    const opts = [('available', 'Available'), ('busy', 'Busy'), ('offline', 'Off today')];
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: AppRadius.pill),
      child: Row(children: [
        for (final o in opts)
          Expanded(
            child: Semantics(
              selected: status == o.$1,
              button: true,
              child: GestureDetector(
                onTap: () {
                  if (status != o.$1) Haptics.light();
                  onChanged(o.$1);
                },
                child: AnimatedContainer(
                  duration: Motion.fast,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: status == o.$1 ? AppColors.gold : Colors.transparent,
                    borderRadius: AppRadius.pill,
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (status == o.$1) ...[
                      Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: o.$1 == 'available'
                              ? const Color(0xFF1F8A4C)
                              : o.$1 == 'busy'
                                  ? const Color(0xFFC93400)
                                  : const Color(0xFF6E6458),
                        ),
                      ),
                      const SizedBox(width: 7),
                    ],
                    Text(o.$2,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: status == o.$1 ? const Color(0xFF17130E) : const Color(0xFFCFC6B8),
                        )),
                  ]),
                ),
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
                ]), style: TextStyle(fontSize: 14, color: AppColors.textPrimary)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: limit == 0 ? 0 : (used / limit).clamp(0, 1).toDouble(),
                    minHeight: 4,
                    backgroundColor: AppColors.cream,
                    color: AppColors.primary,
                  ),
                ),
              ]),
            ),
            Padding(
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
  final bool paying;
  final VoidCallback onTap;
  final VoidCallback onMarkPaid;
  const _TodayRow(
      {super.key, required this.booking, required this.paying, required this.onTap, required this.onMarkPaid});

  @override
  Widget build(BuildContext context) {
    final b = booking;
    final t = DateTime.parse(b['booking_time']).toLocal();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final done = b['status'] == 'completed';
    final paid = paying || b['payment_status'] == 'paid';
    final mins = ((b['service_tiers']?['duration_minutes'] ?? b['services']?['duration_minutes']) as num?)?.toInt();
    final service = [
      b['services']?['service_name'] ?? 'Service',
      if (mins != null) mins >= 60 ? '${mins ~/ 60} h${mins % 60 > 0 ? ' ${mins % 60}' : ''}' : '$mins min',
    ].join(' · ');
    final name = (b['client']?['full_name'] ?? 'Client').toString();
    final amount = money((b['total_price'] as num?) ?? 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 46,
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Text(hm,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Material(
            color: AppColors.card,
            borderRadius: BorderRadius.circular(18),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  border: Border(left: BorderSide(color: paid ? const Color(0xFF1F8A4C) : AppColors.gold, width: 4)),
                ),
                padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
                child: Row(children: [
                  PersonAvatar(name: name, url: b['client']?['avatar_url'], size: 38),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5, color: AppColors.textPrimary)),
                      Text(service,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    ]),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: Motion.of(context),
                    transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                    child: paid
                        ? Container(
                            key: const ValueKey('paid'),
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                                color: const Color(0xFF1F8A4C).withValues(alpha: 0.13), borderRadius: AppRadius.pill),
                            child: Text('✓ Paid $amount',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF1F8A4C))),
                          )
                        : isManualBooking(b) && done
                            ? Pill(key: const ValueKey('walk'), label: 'Walk-in', color: AppColors.textSecondary)
                            : Material(
                                key: const ValueKey('mark'),
                                color: AppColors.surfaceMuted,
                                borderRadius: AppRadius.pill,
                                child: InkWell(
                                  borderRadius: AppRadius.pill,
                                  onTap: onMarkPaid,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    child: Text('Mark paid · $amount',
                                        style: TextStyle(
                                            fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                  ),
                                ),
                              ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ]),
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
    final when = '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]} · '
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    final service = [b['services']?['service_name'], b['service_tiers']?['name']].where((x) => x != null).join(' · ');
    final name = (b['client']?['full_name'] ?? 'Client').toString();
    Widget chip(String t) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(color: AppColors.surfaceMuted, borderRadius: AppRadius.pill),
          child: Text(t, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
        );
    return Material(
      color: AppColors.card,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              PersonAvatar(name: name, url: b['client']?['avatar_url'], size: 46),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  Text(service,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
                ]),
              ),
              Text(money((b['total_price'] as num?) ?? 0),
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              chip(when),
              if (b['at_studio'] == true) chip('At your place') else if (b['at_studio'] == false) chip('Comes to client'),
              if (b['payment_method'] != null) chip(payMethodLabel(b['payment_method'])),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: onDecline,
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.surfaceMuted,
                        foregroundColor: AppColors.textPrimary,
                        minimumSize: const Size(0, 42),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                        shape: const StadiumBorder()),
                    child: const Text('Decline'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 42,
                  child: FilledButton(
                    onPressed: onAccept,
                    style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 42),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                        shape: const StadiumBorder()),
                    child: const Text('Accept'),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }
}
