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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      final results = await SmartMatchService.getRecommendations(
        clientId: uid,
        limit: 15,
      );
      if (mounted) {
        setState(() {
          _recommendations = results;
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
        title: const Text('Recommended For You'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : _recommendations.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: AppSpacing.screenPadding,
                    itemCount: _recommendations.length + 1,
                    itemBuilder: (_, i) {
                      if (i == 0) return _buildHeader();
                      return _buildRecommendationCard(_recommendations[i - 1], i);
                    },
                  ),
                ),
    );
  }

  Widget _buildHeader() {
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
                    'Stylists picked based on your bookings, ratings, and preferences.',
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

  Widget _buildRecommendationCard(Map<String, dynamic> provider, int rank) {
    final name = provider['profiles']?['full_name'] ?? 'Stylist';
    final location = provider['profiles']?['location'] ?? '';
    final rating = (provider['average_rating'] as num?)?.toDouble() ?? 0;
    final reviews = (provider['total_reviews'] as num?)?.toInt() ?? 0;
    final status = provider['availability_status'] ?? 'offline';
    final score = (provider['_matchScore'] as double?) ?? 0;
    final reasons = (provider['_matchReasons'] as List<String>?) ?? [];
    final pid = provider['provider_id'];

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

    final matchPct = (score.clamp(0, 100)).toInt();
    final isTopMatch = rank <= 3;

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
                    // Rank badge + Avatar
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            gradient: AppColors.primaryGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white),
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
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
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
                          ),
                          if (location.isNotEmpty) ...[
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
                          const SizedBox(height: AppSpacing.sm),
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
              // Match reasons
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
