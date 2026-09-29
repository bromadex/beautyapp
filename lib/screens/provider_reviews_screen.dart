import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;
import '../supabase_client.dart';
import '../theme.dart';
import '../widgets/star_rating_widget.dart';
import '../widgets/review_card.dart';

class ProviderReviewsScreen extends StatefulWidget {
  final String providerId;
  const ProviderReviewsScreen({super.key, required this.providerId});

  @override
  State<ProviderReviewsScreen> createState() => _ProviderReviewsScreenState();
}

class _ProviderReviewsScreenState extends State<ProviderReviewsScreen> {
  List<Map<String, dynamic>> _reviews = [];
  Map<String, dynamic>? _providerProfile;
  bool _loading = true;
  Set<String> _myVotes = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        supabase
            .from('provider_profiles')
            .select('average_rating, total_reviews')
            .eq('provider_id', widget.providerId)
            .maybeSingle(),
        supabase
            .from('reviews')
            .select('*, client:profiles!reviews_client_id_fkey(full_name)')
            .eq('provider_id', widget.providerId)
            .order('created_at', ascending: false),
      ]);

      final uid = supabase.auth.currentUser?.id;
      if (uid != null) {
        final votes = await supabase.from('review_votes').select('review_id').eq('user_id', uid);
        _myVotes = {for (final v in votes) v['review_id'] as String};
      }
      if (!mounted) return;
      setState(() {
        _providerProfile = results[0] as Map<String, dynamic>?;
        _reviews = List<Map<String, dynamic>>.from(results[1] as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading reviews: $e')),
        );
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showReplyDialog(Map<String, dynamic> review) async {
    final ctrl = TextEditingController();
    final reply = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply to Review'),
        content: TextField(
          controller: ctrl,
          maxLines: 4,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Write your response...',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Send Reply'),
          ),
        ],
      ),
    );
    ctrl.dispose();

    if (reply == null || reply.isEmpty) return;

    try {
      await supabase.from('reviews').update({
        'provider_reply': reply,
        'provider_reply_at': DateTime.now().toUtc().toIso8601String(),
      }).eq('id', review['id']);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _snack(String msg, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: error ? AppColors.error : null),
    );
  }

  Future<void> _toggleHelpful(Map<String, dynamic> review) async {
    if (supabase.auth.currentUser == null) {
      _snack('Sign in to mark reviews as helpful');
      return;
    }
    try {
      final res = Map<String, dynamic>.from(
          await supabase.rpc('toggle_review_helpful', params: {'p_review': review['id']}) as Map);
      setState(() {
        review['helpful_count'] = res['count'];
        res['voted'] == true ? _myVotes.add(review['id']) : _myVotes.remove(review['id']);
      });
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    }
  }

  Future<void> _report(Map<String, dynamic> review) async {
    if (supabase.auth.currentUser == null) {
      _snack('Sign in to report a review');
      return;
    }
    const reasons = ['Fake or not a real client', 'Rude or abusive', 'Personal information', 'Spam or advertising'];
    String? picked;
    final ok = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.of(ctx).padding.bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Report review', style: Theme.of(ctx).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text('Our team checks every report. The reviewer isn\'t told who reported it.',
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary)),
            const SizedBox(height: 8),
            RadioGroup<String>(
              groupValue: picked,
              onChanged: (v) => setSheet(() => picked = v),
              child: Column(children: [
                for (final r in reasons)
                  RadioListTile<String>(value: r, title: Text(r), contentPadding: EdgeInsets.zero),
              ]),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: picked == null ? null : () => Navigator.pop(ctx, true),
              child: const Text('Send report'),
            ),
          ]),
        ),
      ),
    );
    if (ok != true || picked == null) return;
    try {
      await supabase.rpc('report_review', params: {'p_review': review['id'], 'p_reason': picked});
      _snack('Thanks. We\'ll take a look.');
    } on PostgrestException catch (e) {
      _snack(e.message, error: true);
    }
  }

  /// Build the star distribution bars (5 down to 1).
  Map<int, int> get _ratingDistribution {
    final dist = <int, int>{1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final r in _reviews.where((r) => r['is_hidden'] != true)) {
      final star = (r['rating'] as num?)?.toInt() ?? 0;
      if (star >= 1 && star <= 5) dist[star] = dist[star]! + 1;
    }
    return dist;
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: Center(child: CircularProgressIndicator(color: AppColors.primary)),
      );
    }

    final avg = (_providerProfile?['average_rating'] as num?)?.toDouble() ?? 0.0;
    final total = _providerProfile?['total_reviews'] ?? 0;
    final dist = _ratingDistribution;
    final maxCount = dist.values.fold(0, (a, b) => a > b ? a : b);

    return Scaffold(
      appBar: AppBar(title: const Text('Reviews')),
      body: Column(
        children: [
          // Rating summary card
          Container(
            margin: const EdgeInsets.all(AppSpacing.lg),
            padding: const EdgeInsets.all(AppSpacing.xxl),
            decoration: BoxDecoration(
              color: AppColors.cardLight,
              borderRadius: AppRadius.lgAll,
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                // Large rating number
                Expanded(
                  flex: 2,
                  child: Column(
                    children: [
                      Text(
                        avg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                          height: 1.1,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      StarRatingWidget(rating: avg, size: 22),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        '$total review${total == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: AppColors.textTertiary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: AppSpacing.lg),

                // Distribution bars
                Expanded(
                  flex: 3,
                  child: Column(
                    children: List.generate(5, (i) {
                      final star = 5 - i;
                      final count = dist[star] ?? 0;
                      final fraction = maxCount > 0 ? count / maxCount : 0.0;
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(
                          children: [
                            Text(
                              '$star',
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Icon(TablerIcons.star_filled, size: 14, color: AppColors.warning),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: ClipRRect(
                                borderRadius: AppRadius.smAll,
                                child: LinearProgressIndicator(
                                  value: fraction,
                                  minHeight: 6,
                                  backgroundColor: AppColors.surfaceLight,
                                  valueColor: AlwaysStoppedAnimation(AppColors.warning),
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            SizedBox(
                              width: 24,
                              child: Text(
                                '$count',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textTertiary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),

          // Divider
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Text(
                  'All Reviews',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Spacer(),
                Text(
                  '$total total',
                  style: const TextStyle(color: AppColors.textTertiary, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),

          // Reviews list
          Expanded(
            child: _reviews.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(TablerIcons.message_star, size: 56, color: AppColors.textTertiary),
                        const SizedBox(height: AppSpacing.lg),
                        const Text(
                          'No reviews yet',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        const Text(
                          'Be the first to leave a review!',
                          style: TextStyle(color: AppColors.textTertiary, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    itemCount: _reviews.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
                    itemBuilder: (_, i) {
                      final review = _reviews[i];
                      final isOwner = widget.providerId ==
                          supabase.auth.currentUser?.id;
                      final hasReply = review['provider_reply'] != null &&
                          (review['provider_reply'] as String).isNotEmpty;

                      final uid = supabase.auth.currentUser?.id;
                      final isParty = uid == review['client_id'] || uid == review['provider_id'];
                      final helpful = (review['helpful_count'] as num?)?.toInt() ?? 0;
                      final voted = _myVotes.contains(review['id']);
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (review['is_hidden'] == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 6),
                              child: Text('Hidden by BeauTap after a report. Only you can see it.',
                                  style: TextStyle(fontSize: 12, color: AppColors.error)),
                            ),
                          ReviewCard(review: review),
                          if (review['is_hidden'] != true)
                            Row(children: [
                              TextButton.icon(
                                onPressed: isParty ? null : () => _toggleHelpful(review),
                                icon: Icon(voted ? TablerIcons.thumb_up_filled : TablerIcons.thumb_up, size: 16),
                                label: Text(helpful > 0 ? 'Helpful · $helpful' : 'Helpful'),
                                style: TextButton.styleFrom(
                                  foregroundColor: voted ? AppColors.primary : AppColors.textSecondary,
                                  textStyle: const TextStyle(fontSize: 13),
                                ),
                              ),
                              if (uid != review['client_id'])
                                TextButton(
                                  onPressed: () => _report(review),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.textTertiary,
                                    textStyle: const TextStyle(fontSize: 13),
                                  ),
                                  child: const Text('Report'),
                                ),
                            ]),
                          if (isOwner && !hasReply)
                            Padding(
                              padding: const EdgeInsets.only(
                                  left: AppSpacing.md,
                                  bottom: AppSpacing.md),
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: () =>
                                      _showReplyDialog(review),
                                  icon: const Icon(TablerIcons.arrow_back_up,
                                      size: 16),
                                  label: const Text('Reply'),
                                  style: TextButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    textStyle:
                                        const TextStyle(fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
