import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _verification;
  Map<String, dynamic>? _providerProfile;
  Map<String, dynamic>? _subscription;
  bool _isAdmin = false;
  bool _loading = true;
  late AnimationController _animCtrl;

  // New dashboard data
  Map<String, dynamic>? _nextBooking;
  double _weeklyEarnings = 0;
  int _weeklyBookingsCount = 0;
  int _totalReviews = 0;
  double _avgRating = 0;
  List<Map<String, dynamic>> _recentActivity = [];

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _loadData();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = supabase.auth.currentUser!.id;

    final profile = await supabase
        .from('profiles').select().eq('id', userId).single();

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
    int weeklyBookingsCount = 0;
    int totalReviews = 0;
    double avgRating = 0;
    List<Map<String, dynamic>> recentActivity = [];

    if (profile['user_type'] == 'provider') {
      try {
        providerProfile = await supabase
            .from('provider_profiles').select()
            .eq('provider_id', userId).single();
      } catch (_) {}

      try {
        final sub = await supabase
            .from('subscriptions')
            .select()
            .eq('provider_id', userId)
            .maybeSingle();
        subscription = sub;
      } catch (_) {}

      // Next upcoming booking
      try {
        final now = DateTime.now().toIso8601String();
        nextBooking = await supabase
            .from('bookings')
            .select('*, services(service_name), profiles!bookings_client_id_fkey(full_name)')
            .eq('provider_id', userId)
            .inFilter('status', ['confirmed', 'en_route', 'arrived', 'in_progress'])
            .gte('booking_date', now.substring(0, 10))
            .order('booking_date', ascending: true)
            .order('booking_time', ascending: true)
            .limit(1)
            .maybeSingle();
      } catch (_) {}

      // Weekly earnings
      try {
        final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
        final payments = await supabase
            .from('payments')
            .select('amount')
            .eq('provider_id', userId)
            .eq('status', 'completed')
            .gte('created_at', weekAgo);
        for (final p in (payments as List)) {
          weeklyEarnings += (p['amount'] as num).toDouble();
        }
      } catch (_) {}

      // Weekly bookings count
      try {
        final weekAgo = DateTime.now().subtract(const Duration(days: 7)).toIso8601String();
        final bookings = await supabase
            .from('bookings')
            .select('id')
            .eq('provider_id', userId)
            .gte('created_at', weekAgo);
        weeklyBookingsCount = (bookings as List).length;
      } catch (_) {}

      // Reviews stats
      try {
        final reviews = await supabase
            .from('reviews')
            .select('rating')
            .eq('provider_id', userId);
        final list = reviews as List;
        totalReviews = list.length;
        if (list.isNotEmpty) {
          double sum = 0;
          for (final r in list) {
            sum += (r['rating'] as num).toDouble();
          }
          avgRating = sum / list.length;
        }
      } catch (_) {}

      // Recent activity (last 5 events: reviews, bookings, payments)
      try {
        final recentReviews = await supabase
            .from('reviews')
            .select('id, rating, comment, created_at, profiles!reviews_client_id_fkey(full_name)')
            .eq('provider_id', userId)
            .order('created_at', ascending: false)
            .limit(3);
        for (final r in (recentReviews as List)) {
          recentActivity.add({
            'type': 'review',
            'data': r,
            'created_at': r['created_at'],
          });
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
          recentActivity.add({
            'type': 'booking',
            'data': b,
            'created_at': b['created_at'],
          });
        }
      } catch (_) {}

      recentActivity.sort((a, b) =>
          (b['created_at'] as String).compareTo(a['created_at'] as String));
      if (recentActivity.length > 5) {
        recentActivity = recentActivity.sublist(0, 5);
      }
    }

    if (mounted) {
      setState(() {
        _profile = profile;
        _verification = verification;
        _providerProfile = providerProfile;
        _subscription = subscription;
        _isAdmin = isAdmin;
        _nextBooking = nextBooking;
        _weeklyEarnings = weeklyEarnings;
        _weeklyBookingsCount = weeklyBookingsCount;
        _totalReviews = totalReviews;
        _avgRating = avgRating;
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
              SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(strokeWidth: 3, color: AppColors.primary),
              ),
              const SizedBox(height: 16),
              Text('Loading...', style: TextStyle(color: AppColors.textTertiary, fontSize: 13)),
            ],
          ),
        ),
      );
    }

    final name       = _profile?['full_name'] ?? 'User';
    final userType   = _profile?['user_type'] ?? 'client';
    final isProvider = userType == 'provider';
    final isVerified = _profile?['is_verified'] == true;
    final vStatus    = _verification?['status'];
    final bool hasActiveSubscription = _subscription != null &&
        _subscription!['status'] == 'active';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(name, isProvider, isVerified),

          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: CurvedAnimation(parent: _animCtrl, curve: Curves.easeOut),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isVerified) ...[
                          _VerificationBanner(
                            status: vStatus,
                            onTap: () {
                              if (vStatus == null || vStatus == 'rejected') {
                                context.go('/verify');
                              } else {
                                context.go('/verify/pending');
                              }
                            },
                          ),
                          const SizedBox(height: 16),
                        ],

                        if (isProvider && isVerified) ...[
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
                            const SizedBox(height: 16),
                          ],

                          if (!hasActiveSubscription) ...[
                            _WarningBanner(
                              text: 'No active subscription — your profile is hidden.',
                              onTap: () => context.go('/provider/subscription'),
                            ),
                            const SizedBox(height: 16),
                          ],

                          // Next Booking Card
                          if (_nextBooking != null) ...[
                            _NextBookingCard(booking: _nextBooking!),
                            const SizedBox(height: 16),
                          ],

                          // Weekly Stats
                          _WeeklyStatsRow(
                            earnings: _weeklyEarnings,
                            bookingsCount: _weeklyBookingsCount,
                            avgRating: _avgRating,
                            totalReviews: _totalReviews,
                          ),
                          const SizedBox(height: 20),

                          // Quick Actions (deprioritized)
                          Text('Quick Actions', style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textTertiary,
                            letterSpacing: 0.5,
                          )),
                          const SizedBox(height: 10),
                          _buildProviderTiles(context),
                          const SizedBox(height: 20),

                          // Recent Activity
                          if (_recentActivity.isNotEmpty) ...[
                            Text('Recent Activity', style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textTertiary,
                              letterSpacing: 0.5,
                            )),
                            const SizedBox(height: 10),
                            _ActivityFeed(activities: _recentActivity),
                          ],
                        ],

                        if (isProvider && isVerified && _providerProfile == null) ...[
                          const SizedBox(height: 8),
                          _SetupCard(onTap: () => context.go('/provider/profile/edit')),
                        ],

                        if (!isProvider && isVerified) _buildClientTiles(context),
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

  Widget _buildSliverAppBar(String name, bool isProvider, bool isVerified) {
    return SliverAppBar(
      expandedHeight: isProvider ? 200 : 180,
      pinned: true,
      backgroundColor: AppColors.primary,
      surfaceTintColor: Colors.transparent,
      title: const Text(
        'Beauty Home Services',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18),
      ),
      actions: [
        if (_isAdmin)
          IconButton(
            icon: const Icon(Icons.admin_panel_settings, color: Colors.white),
            tooltip: 'Admin Panel',
            onPressed: () => context.go('/admin/verify'),
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
              padding: const EdgeInsets.fromLTRB(20, 56, 20, 20),
              child: Row(
                children: [
                  Container(
                    width: 56, height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white38, width: 2),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Welcome back,', style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.8))),
                        Text(name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 6),
                        Row(children: [
                          _Badge(label: isProvider ? 'Provider' : 'Client'),
                          const SizedBox(width: 6),
                          _Badge(label: isVerified ? 'Verified' : 'Unverified', isPositive: isVerified),
                          if (isProvider && _avgRating > 0) ...[
                            const SizedBox(width: 6),
                            _Badge(label: '${_avgRating.toStringAsFixed(1)} ★', isPositive: true),
                          ],
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
    );
  }

  Widget _buildProviderTiles(BuildContext context) {
    final tiles = [
      _TileData(Icons.person_outline, 'Edit Profile', AppColors.info, '/provider/profile/edit'),
      _TileData(Icons.content_cut_rounded, 'My Services', AppColors.secondary, '/provider/services'),
      _TileData(Icons.photo_library_outlined, 'Gallery', AppColors.accent, '/provider/gallery'),
      _TileData(Icons.calendar_month_rounded, 'Bookings', AppColors.warning, '/provider/bookings'),
      _TileData(Icons.workspace_premium_rounded, 'Subscription', AppColors.success, '/provider/subscription'),
      _TileData(Icons.account_balance_wallet_rounded, 'Earnings', const Color(0xFF0EA5E9), '/earnings'),
      _TileData(Icons.public_outlined, 'Public Profile', AppColors.primary, '/provider/${supabase.auth.currentUser!.id}'),
      _TileData(Icons.star_rounded, 'Reviews', const Color(0xFFD97706), '/provider/${supabase.auth.currentUser!.id}/reviews'),
    ];

    return _TileGrid(tiles: tiles);
  }

  Widget _buildClientTiles(BuildContext context) {
    final tiles = [
      _TileData(Icons.search_rounded, 'Browse Stylists', AppColors.primary, '/browse'),
      _TileData(Icons.calendar_today_outlined, 'My Bookings', AppColors.info, '/client/bookings'),
      _TileData(Icons.favorite_rounded, 'Favourites', AppColors.error, '/favorites'),
    ];

    return _TileGrid(tiles: tiles);
  }
}

// --- Next Booking Card ---

class _NextBookingCard extends StatelessWidget {
  final Map<String, dynamic> booking;
  const _NextBookingCard({required this.booking});

  @override
  Widget build(BuildContext context) {
    final clientName = booking['profiles']?['full_name'] ?? 'Client';
    final serviceName = booking['services']?['service_name'] ?? 'Service';
    final bookingDate = booking['booking_date'] ?? '';
    final bookingTime = booking['booking_time'] ?? '';
    final status = booking['status'] ?? 'confirmed';
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
    if (bookingDate.isNotEmpty) {
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
      } catch (_) {}
    }

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFE91E8C), Color(0xFFAB47BC)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: AppRadius.lgAll,
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'NEXT BOOKING',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.9), letterSpacing: 1),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    StatusColors.label(status),
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(Icons.access_time_rounded, color: Colors.white.withValues(alpha: 0.9), size: 18),
                const SizedBox(width: 6),
                Text(
                  '$dateDisplay at $timeDisplay',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '$serviceName · $clientName',
              style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.85)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/provider/bookings/$bookingId'),
                      icon: const Icon(Icons.visibility_outlined, size: 16),
                      label: const Text('View'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.4)),
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 36,
                    child: FilledButton.icon(
                      onPressed: () => context.go('/chat/$bookingId'),
                      icon: const Icon(Icons.chat_bubble_outline_rounded, size: 16),
                      label: const Text('Chat'),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: AppColors.primary,
                        padding: EdgeInsets.zero,
                        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.smAll),
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

// --- Weekly Stats Row ---

class _WeeklyStatsRow extends StatelessWidget {
  final double earnings;
  final int bookingsCount;
  final double avgRating;
  final int totalReviews;
  const _WeeklyStatsRow({
    required this.earnings,
    required this.bookingsCount,
    required this.avgRating,
    required this.totalReviews,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _StatCard(
          label: 'This Week',
          value: 'R${earnings.toStringAsFixed(0)}',
          icon: Icons.account_balance_wallet_rounded,
          color: AppColors.success,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label: 'Bookings',
          value: '$bookingsCount',
          icon: Icons.calendar_month_rounded,
          color: AppColors.info,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          label: 'Rating',
          value: avgRating > 0 ? avgRating.toStringAsFixed(1) : '—',
          icon: Icons.star_rounded,
          color: const Color(0xFFD97706),
          subtitle: totalReviews > 0 ? '$totalReviews reviews' : null,
        )),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final String? subtitle;
  const _StatCard({required this.label, required this.value, required this.icon, required this.color, this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: AppRadius.mdAll,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 16),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w500),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 1),
            Text(subtitle!, style: TextStyle(fontSize: 10, color: AppColors.textTertiary)),
          ],
        ],
      ),
    );
  }
}

// --- Availability Toggle ---

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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
              color: color,
              size: 22,
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
                  isAvailable
                      ? 'Clients can find and book you'
                      : 'You won\'t appear in search results',
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

// --- Activity Feed ---

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
        itemCount: activities.length,
        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade100),
        itemBuilder: (context, index) {
          final activity = activities[index];
          return _ActivityItem(activity: activity);
        },
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

    if (type == 'review') {
      icon = Icons.star_rounded;
      color = const Color(0xFFD97706);
      final clientName = data['profiles']?['full_name'] ?? 'A client';
      final rating = data['rating'] ?? 0;
      title = '$clientName left a $rating-star review';
      final comment = data['comment'] as String? ?? '';
      subtitle = comment.isNotEmpty
          ? (comment.length > 60 ? '${comment.substring(0, 60)}…' : comment)
          : 'No comment';
    } else {
      final bookingStatus = data['status'] ?? 'pending';
      icon = _bookingIcon(bookingStatus);
      color = StatusColors.foreground(bookingStatus);
      final clientName = data['profiles']?['full_name'] ?? 'A client';
      final serviceName = data['services']?['service_name'] ?? 'service';
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
            width: 36, height: 36,
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
              ],
            ),
          ),
          if (timeAgo.isNotEmpty)
            Text(timeAgo, style: TextStyle(fontSize: 11, color: AppColors.textTertiary)),
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

// --- Tile Components (kept for Quick Actions + Client) ---

class _TileData {
  final IconData icon;
  final String label;
  final Color color;
  final String route;
  const _TileData(this.icon, this.label, this.color, this.route);
}

class _TileGrid extends StatelessWidget {
  final List<_TileData> tiles;
  const _TileGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 450 ? 4 : 3;
        final spacing = 10.0;
        final tileWidth = (constraints.maxWidth - spacing * (crossCount - 1)) / crossCount;

        return Wrap(
          spacing: spacing,
          runSpacing: 12,
          children: tiles.map((t) => SizedBox(
            width: tileWidth,
            child: _DashTile(
              icon: t.icon,
              label: t.label,
              color: t.color,
              onTap: () => context.go(t.route),
            ),
          )).toList(),
        );
      },
    );
  }
}

class _DashTile extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _DashTile({required this.icon, required this.label, required this.color, required this.onTap});

  @override
  State<_DashTile> createState() => _DashTileState();
}

class _DashTileState extends State<_DashTile> {
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
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: _hovering ? widget.color.withValues(alpha: 0.08) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovering ? widget.color.withValues(alpha: 0.3) : Colors.grey.shade200,
            ),
            boxShadow: _hovering
                ? [BoxShadow(color: widget.color.withValues(alpha: 0.12), blurRadius: 12, offset: const Offset(0, 4))]
                : [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: _hovering ? 48 : 44,
                height: _hovering ? 48 : 44,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      widget.color.withValues(alpha: _hovering ? 0.2 : 0.12),
                      widget.color.withValues(alpha: _hovering ? 0.1 : 0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(widget.icon, color: widget.color, size: _hovering ? 24 : 22),
              ),
              const SizedBox(height: 8),
              Text(
                widget.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: _hovering ? widget.color : AppColors.textPrimary,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// --- Supporting Widgets ---

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

class _Badge extends StatelessWidget {
  final String label;
  final bool isPositive;
  const _Badge({required this.label, this.isPositive = false});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isPositive ? AppColors.success.withValues(alpha: 0.3) : Colors.white.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white)),
    );
  }
}
