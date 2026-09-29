import 'package:flutter/material.dart';
import 'package:flutter_tabler_icons/flutter_tabler_icons.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AdminVerificationScreen extends StatefulWidget {
  const AdminVerificationScreen({super.key});

  @override
  State<AdminVerificationScreen> createState() =>
      _AdminVerificationScreenState();
}

class _AdminVerificationScreenState
    extends State<AdminVerificationScreen> {
  List<Map<String, dynamic>> _pending = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await supabase
        .from('verifications')
        .select('*, profiles(full_name, user_type, phone)')
        .eq('status', 'pending')
        .order('submitted_at');
    if (mounted) {
      setState(() {
        _pending = List<Map<String, dynamic>>.from(data);
        _loading = false;
      });
    }
  }

  Future<String> _getSignedUrl(String path) async {
    final res = await supabase.storage
        .from('verification-docs')
        .createSignedUrl(path, 60);
    return res;
  }

  Future<void> _review(
      String verificationId, String userId, bool approve,
      {String? note}) async {
    await supabase.from('verifications').update({
      'status': approve ? 'approved' : 'rejected',
      'admin_note': note,
      'reviewed_at': DateTime.now().toUtc().toIso8601String(),
    }).eq('id', verificationId);

    if (approve) {
      await supabase
          .from('profiles')
          .update({'is_verified': true})
          .eq('id', userId);
    }

    _load();
  }

  void _showRejectDialog(String verificationId, String userId) {
    final noteCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                TablerIcons.ban,
                color: AppColors.error,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('Reject Submission'),
          ],
        ),
        content: TextField(
          controller: noteCtrl,
          decoration: InputDecoration(
            labelText: 'Reason (shown to user)',
            hintText: 'e.g. Photo is blurry, ID not readable...',
            border: OutlineInputBorder(
              borderRadius: AppRadius.mdAll,
            ),
          ),
          maxLines: 3,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: AppColors.textSecondary),
            ),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _review(verificationId, userId, false,
                  note: noteCtrl.text.trim());
            },
            icon: const Icon(TablerIcons.x, size: 18),
            label: const Text('Reject'),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showDocuments(String selfiePath, String idPath) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.xxl),
          decoration: BoxDecoration(
            color: AppColors.card,
            borderRadius: AppRadius.lgAll,
          ),
          child: CircularProgressIndicator(
            color: AppColors.primary,
          ),
        ),
      ),
    );

    final selfieUrl = await _getSignedUrl(selfiePath);
    final idUrl = await _getSignedUrl(idPath);

    if (!mounted) return;
    Navigator.pop(context);

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.info.withValues(alpha: 0.1),
                borderRadius: AppRadius.smAll,
              ),
              child: Icon(
                TablerIcons.photo,
                color: AppColors.info,
                size: 20,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            const Text('Submitted Documents'),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDocLabel('Selfie Photo', TablerIcons.camera_selfie),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network(selfieUrl),
              ),
              const SizedBox(height: AppSpacing.xl),
              _buildDocLabel('ID Document', TablerIcons.credit_card),
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: AppRadius.mdAll,
                child: Image.network(idUrl),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildDocLabel(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.textSecondary),
        const SizedBox(width: AppSpacing.sm),
        Text(
          text,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verifications'),
        actions: [
          // Pending count badge
          if (!_loading && _pending.isNotEmpty)
            Center(
              child: Container(
                margin: const EdgeInsets.only(right: AppSpacing.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: AppRadius.smAll,
                ),
                child: Text(
                  '${_pending.length} pending',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(TablerIcons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : _pending.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  padding: AppSpacing.screenPadding,
                  itemCount: _pending.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (_, i) => _buildVerificationCard(_pending[i]),
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
              color: AppColors.success.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              TablerIcons.circle_check,
              size: 56,
              color: AppColors.success,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'All Caught Up',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'No pending verifications to review.',
            style: TextStyle(
              fontSize: 14,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVerificationCard(Map<String, dynamic> v) {
    final profile = v['profiles'] as Map<String, dynamic>;
    final name = profile['full_name'] ?? 'Unknown';
    final type = profile['user_type'] ?? '';
    final phone = profile['phone'] ?? '';
    final submittedAt = DateTime.tryParse(v['submitted_at'] ?? '');

    return Container(
      decoration: BoxDecoration(
        color: AppColors.card,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // User info header
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                // Avatar
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    gradient: AppColors.primaryGradient,
                    borderRadius: AppRadius.mdAll,
                  ),
                  child: Center(
                    child: Text(
                      name.isNotEmpty ? name[0].toUpperCase() : '?',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          // User type badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.secondary.withValues(alpha: 0.1),
                              borderRadius: AppRadius.smAll,
                            ),
                            child: Text(
                              type.toString().isNotEmpty
                                  ? type[0].toUpperCase() +
                                      type.substring(1)
                                  : 'User',
                              style: TextStyle(
                                color: AppColors.secondary,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          if (phone.toString().isNotEmpty) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              phone,
                              style: TextStyle(
                                color: AppColors.textTertiary,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                // Status badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                  decoration: BoxDecoration(
                    color: StatusColors.background('pending'),
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    StatusColors.label('pending'),
                    style: TextStyle(
                      color: StatusColors.foreground('pending'),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Submitted time
          if (submittedAt != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  Icon(
                    TablerIcons.clock,
                    size: 14,
                    color: AppColors.textTertiary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Submitted ${submittedAt.toLocal().toString().substring(0, 16)}',
                    style: TextStyle(
                      color: AppColors.textTertiary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: AppSpacing.md),

          // Divider
          Divider(height: 1, color: AppColors.border),

          // Action buttons
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              children: [
                // View Documents button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _showDocuments(
                        v['selfie_url'], v['id_document_url']),
                    icon: const Icon(
                      TablerIcons.eye,
                      size: 18,
                    ),
                    label: const Text('View Documents'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: BorderSide(
                        color: AppColors.info.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll,
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.md,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Approve / Reject row
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            _showRejectDialog(v['id'], v['user_id']),
                        icon: const Icon(TablerIcons.x, size: 18),
                        label: const Text('Reject'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.error,
                          side: BorderSide(color: AppColors.error),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () =>
                            _review(v['id'], v['user_id'], true),
                        icon: const Icon(TablerIcons.check, size: 18),
                        label: const Text('Approve'),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.success,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
