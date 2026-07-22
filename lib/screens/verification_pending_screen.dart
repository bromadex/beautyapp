import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class VerificationPendingScreen extends StatefulWidget {
  const VerificationPendingScreen({super.key});

  @override
  State<VerificationPendingScreen> createState() =>
      _VerificationPendingScreenState();
}

class _VerificationPendingScreenState
    extends State<VerificationPendingScreen> {
  Map<String, dynamic>? _verification;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final data = await supabase
          .from('verifications')
          .select()
          .eq('user_id', userId)
          .order('submitted_at', ascending: false)
          .limit(1)
          .single();
      if (mounted) setState(() => _verification = data);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final status = _verification?['status'] ?? 'pending';
    final adminNote = _verification?['admin_note'];
    final isRejected = status == 'rejected';

    final statusColor = isRejected ? AppColors.error : AppColors.warning;
    final statusIcon = isRejected
        ? Icons.cancel_rounded
        : Icons.hourglass_top_rounded;

    return Scaffold(
      appBar: AppBar(title: const Text('Verification Status')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xxxl),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Status icon with colored circle background
              Center(
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: statusColor.withValues(alpha: 0.1),
                  ),
                  child: Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor.withValues(alpha: 0.15),
                      ),
                      child: Icon(
                        statusIcon,
                        size: 44,
                        color: statusColor,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Status title
              Text(
                isRejected ? 'Verification Rejected' : 'Under Review',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.md),

              // Description
              Text(
                isRejected
                    ? 'Your submission was not approved. Please re-submit with clearer photos.'
                    : 'Your documents have been submitted and are being reviewed. This usually takes 24 hours.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),

              // Admin note
              if (adminNote != null) ...[
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.08),
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(
                      color: AppColors.error.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline_rounded,
                        size: 18,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Admin Note',
                              style: TextStyle(
                                color: AppColors.error,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            Text(
                              adminNote.toString(),
                              style: TextStyle(
                                color: AppColors.error.withValues(alpha: 0.85),
                                fontSize: 13,
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxxl),

              // Pending status indicator (only when not rejected)
              if (!isRejected)
                Container(
                  padding: AppSpacing.cardPadding,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: AppRadius.mdAll,
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.1),
                          borderRadius: AppRadius.smAll,
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          size: 20,
                          color: AppColors.info,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Estimated Review Time',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Within 24 hours',
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

              if (!isRejected) const SizedBox(height: AppSpacing.xxl),

              // Actions
              if (isRejected)
                FilledButton.icon(
                  onPressed: () => context.go('/verify'),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Re-Submit Documents'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll,
                    ),
                  ),
                ),
              if (isRejected) const SizedBox(height: AppSpacing.md),

              TextButton(
                onPressed: () => context.go('/home'),
                child: Text(
                  'Back to Home',
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
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
