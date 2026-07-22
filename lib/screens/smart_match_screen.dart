import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../services/smart_match_service.dart';
import '../theme.dart';

class SmartMatchScreen extends StatefulWidget {
  const SmartMatchScreen({super.key});

  @override
  State<SmartMatchScreen> createState() => _SmartMatchScreenState();
}

class _SmartMatchScreenState extends State<SmartMatchScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _recommendations = [];
  List<Map<String, dynamic>> _nearbyProviders = [];
  List<Map<String, dynamic>> _topRated = [];
  String _clientLocation = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser?.id;
      if (uid == null) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final profile = await supabase
          .from('profiles')
          .select('location')
          .eq('id', uid)
          .maybeSingle();
      _clientLocation = (profile?['location'] ?? '').toString();

      final results = await Future.wait([
        SmartMatchService.getRecommendations(clientId: uid, limit: 10),
        SmartMatchService.getNearbyProviders(clientLocation: _clientLocation, limit: 10),
        SmartMatchService.getTopRated(location: _clientLocation, limit: 10),
      ]);

      if (mounted) {
        setState(() {
          _recommendations = results[0];
          _nearbyProviders = results[1];
          _topRated = results[2];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading recommendations: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('For You'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : (_recommendations.isEmpty && _nearbyProviders.isEmpty && _topRated.isEmpty)
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: AppSpacing.screenPadding,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      _buildHeroBanner(),
                      if (_recommendations.isNotEmpty) ...[
                        _buildSectionHeader(
                          Icons.auto_awesome_rounded,
                          'Picked For You',
                          'Based on your bookings and preferences',
                        ),
                        ..._recommendations.asMap().entries.map(
                            (e) => _buildProviderCard(e.value, rank: e.key + 1)),
                      ],
                      if (_nearbyProviders.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionHeader(
                          Icons.near_me_rounded,
                          'Near You',
                          _clientLocation.isNotEmpty
                              ? 'Stylists in $_clientLocation'
                              : 'Stylists in your area',
                        ),
                        ..._nearbyProviders.map(
                            (p) => _buildProviderCard(p, showLocation: true)),
                      ],
                      if (_topRated.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.lg),
                        _buildSectionHeader(
                          Icons.star_rounded,
                          'Top Rated',
                          'Highest rated stylists',
                        ),
                        ..._topRated.map(
                            (p) => _buildProviderCard(p, showRatingBadge: true)),
                      ],
                      const SizedBox(height: AppSpacing.xxl),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHeroBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        decoration: BoxDecoration(
          gradient: AppColors.heroGradient,
          borderRadius: AppRadius.lgAll,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your Perfect Match',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Discover stylists based on your preferences, location, and top ratings.',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 28),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(IconData icon, String title, String subtitle) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: AppRadius.smAll,
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                )),
                Text(subtitle, style: const TextStyle(
                  fontSize: 12, color: AppColors.textTertiary,
                )),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: AppSpacing.screenPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.auto_awesome_rounded, color: AppColors.primary, size: 40),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text('No Recommendations Yet', style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Book a few services and we\'ll learn your preferences to recommend the best stylists for you.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
            const SizedBox(height: AppSpacing.xxl),
            FilledButton.icon(
              onPressed: () => context.go('/browse'),
              icon: const Icon(Icons.search_rounded),
              label: const Text('Browse Stylists'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderCard(
    Map<String, dynamic> provider, {
    int? rank,
    bool showLocation = false,
    bool showRatingBadge = false,
  }) {
    final name = provider['profiles']?['full_name'] ?? 'Stylist';
    final location = provider['profiles']?['location'] ?? '';
    final rating = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final status = provider['availability_status'] ?? 'offline';
    final reasons = (provider['_matchReasons'] as List<String>?) ?? [];
    final pid = provider['provider_id'];
    final score = (provider['_matchScore'] as double?) ?? 0;

    Color statusColor;
    String statusLabel;
    switch (status) {
      case 'available':
        statusColor = AppColors.available;
        statusLabel = 'Available';
        break;
      case 'busy':
        statusColor = AppColors.busy;
        statusLabel = 'Busy';
        break;
      default:
        statusColor = AppColors.offline;
        statusLabel = 'Offline';
    }

    final isTopMatch = rank != null && rank <= 3;
    final matchPct = (score.clamp(0, 100)).toInt();

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        onTap: () => context.push('/provider/$pid'),
        borderRadius: AppRadius.lgAll,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: AppRadius.lgAll,
            border: Border.all(
              color: isTopMatch ? AppColors.primary.withValues(alpha: 0.3) : Colors.grey.shade200,
            ),
            boxShadow: isTopMatch
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))]
                : null,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(AppSpacing.lg),
                child: Row(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: const BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ),
                        if (isTopMatch)
                          Positioned(
                            top: -4,
                            right: -4,
                            child: Container(
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: rank == 1 ? AppColors.warning : AppColors.primary,
                                shape: BoxShape.circle,
                                border: Border.all(color: Colors.white, width: 2),
                              ),
                              child: Center(
                                child: Text(
                                  '$rank',
                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        if (showRatingBadge && rating >= 4.0)
                          Positioned(
                            bottom: -2,
                            right: -4,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                              decoration: BoxDecoration(
                                color: AppColors.warning,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star_rounded, size: 10, color: Colors.white),
                                  Text(
                                    rating.toStringAsFixed(1),
                                    style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: AppSpacing.lg),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (rank != null) ...[
                                const SizedBox(width: AppSpacing.sm),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: _matchColor(matchPct).withValues(alpha: 0.1),
                                    borderRadius: AppRadius.smAll,
                                  ),
                                  child: Text(
                                    '$matchPct% match',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: _matchColor(matchPct),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          if (location.isNotEmpty && (showLocation || rank == null)) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(Icons.location_on_outlined, size: 13, color: AppColors.textTertiary),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    location,
                                    style: const TextStyle(color: AppColors.textTertiary, fontSize: 12),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xs),
                          Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                              ),
                              const SizedBox(width: 4),
                              Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w600)),
                              if (reviews > 0) ...[
                                const SizedBox(width: AppSpacing.md),
                                const Icon(Icons.star_rounded, size: 14, color: AppColors.warning),
                                const SizedBox(width: 2),
                                Text(
                                  '${rating.toStringAsFixed(1)} ($reviews)',
                                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
                  ],
                ),
              ),
              if (reasons.isNotEmpty) ...[
                Divider(height: 1, color: Colors.grey.shade100),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 14, color: AppColors.primary.withValues(alpha: 0.6)),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          reasons.join(' · '),
                          style: TextStyle(fontSize: 11, color: AppColors.primary.withValues(alpha: 0.8), fontWeight: FontWeight.w500),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _matchColor(int pct) {
    if (pct >= 70) return AppColors.success;
    if (pct >= 40) return AppColors.info;
    return AppColors.warning;
  }
}
