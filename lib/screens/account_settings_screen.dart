import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});
  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  bool _loading = false;
  bool _isDeactivated = false;

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final uid = supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final profile = await supabase
          .from('profiles')
          .select('is_deactivated')
          .eq('id', uid)
          .single();
      if (mounted) {
        setState(() => _isDeactivated = profile['is_deactivated'] == true);
      }
    } catch (_) {}
  }

  Future<void> _toggleDeactivation() async {
    final newState = !_isDeactivated;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        title: Text(newState ? 'Deactivate Account?' : 'Reactivate Account?'),
        content: Text(newState
            ? 'Your profile will be hidden from search results and clients won\'t be able to book you. You can reactivate anytime by signing back in.'
            : 'Your profile will be visible again and clients can find and book you.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: newState ? AppColors.warning : AppColors.success,
            ),
            child: Text(newState ? 'Deactivate' : 'Reactivate'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _loading = true);
    try {
      final uid = supabase.auth.currentUser!.id;
      await supabase
          .from('profiles')
          .update({'is_deactivated': newState})
          .eq('id', uid);

      if (newState) {
        // Sign out after deactivation
        await supabase.auth.signOut();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Account deactivated. Sign in anytime to reactivate.'),
              backgroundColor: AppColors.warning,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
          );
          context.go('/login');
        }
      } else {
        if (mounted) {
          setState(() {
            _isDeactivated = false;
            _loading = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Account reactivated!'),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _deleteAccount() async {
    // Step 1: First confirmation
    final firstConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        icon: Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: AppColors.error.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.warning_rounded, color: AppColors.error, size: 28),
        ),
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your account and all your data including:\n\n'
          '• Your profile and personal information\n'
          '• All bookings and booking history\n'
          '• Messages and reviews\n'
          '• Services, gallery, and promotions\n'
          '• Subscription and payment records\n\n'
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            child: const Text('Continue'),
          ),
        ],
      ),
    );

    if (firstConfirm != true) return;

    // Step 2: Type DELETE confirmation
    final deleteController = TextEditingController();
    final secondConfirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        title: const Text('Confirm Deletion'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Type DELETE below to confirm you want to permanently delete your account.'),
            const SizedBox(height: 16),
            TextField(
              controller: deleteController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Type DELETE',
                border: OutlineInputBorder(borderRadius: AppRadius.mdAll),
                filled: true,
                fillColor: AppColors.error.withValues(alpha: 0.04),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ListenableBuilder(
            listenable: deleteController,
            builder: (_, __) {
              final enabled = deleteController.text.trim().toUpperCase() == 'DELETE';
              return FilledButton(
                onPressed: enabled ? () => Navigator.pop(ctx, true) : null,
                style: FilledButton.styleFrom(backgroundColor: AppColors.error),
                child: const Text('Delete Forever'),
              );
            },
          ),
        ],
      ),
    );

    deleteController.dispose();
    if (secondConfirm != true) return;

    // Step 3: Perform deletion
    setState(() => _loading = true);
    try {
      await supabase.rpc('delete_user_account');
      await supabase.auth.signOut();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Your account has been deleted.'),
            backgroundColor: AppColors.textSecondary,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          ),
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete account: $e'),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = supabase.auth.currentUser?.email ?? '';

    return Scaffold(
      appBar: AppBar(title: const Text('Account Settings')),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  const SizedBox(height: 16),
                  Text('Please wait...', style: TextStyle(color: AppColors.textTertiary)),
                ],
              ),
            )
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: ListView(
                  padding: AppSpacing.screenPadding,
                  children: [
                    // Account info
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: AppRadius.lgAll,
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 48, height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.person_outline, color: AppColors.primary),
                          ),
                          const SizedBox(width: AppSpacing.lg),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Signed in as', style: TextStyle(
                                  fontSize: 12, color: AppColors.textTertiary,
                                )),
                                const SizedBox(height: 2),
                                Text(email, style: const TextStyle(
                                  fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textPrimary,
                                )),
                              ],
                            ),
                          ),
                          if (_isDeactivated)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text('Deactivated', style: TextStyle(
                                fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.warning,
                              )),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Deactivate section
                    const Text('Account Status', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textTertiary, letterSpacing: 0.5,
                    )),
                    const SizedBox(height: AppSpacing.md),
                    _SettingsTile(
                      icon: _isDeactivated
                          ? Icons.toggle_on_rounded
                          : Icons.toggle_off_rounded,
                      iconColor: _isDeactivated ? AppColors.success : AppColors.warning,
                      title: _isDeactivated ? 'Reactivate Account' : 'Deactivate Account',
                      subtitle: _isDeactivated
                          ? 'Make your profile visible again'
                          : 'Temporarily hide your profile. You can reactivate anytime.',
                      onTap: _toggleDeactivation,
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Danger zone
                    const Text('Danger Zone', style: TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.error, letterSpacing: 0.5,
                    )),
                    const SizedBox(height: AppSpacing.md),
                    _SettingsTile(
                      icon: Icons.delete_forever_rounded,
                      iconColor: AppColors.error,
                      title: 'Delete Account',
                      subtitle: 'Permanently delete your account and all data. This cannot be undone.',
                      onTap: _deleteAccount,
                      isDanger: true,
                    ),

                    const SizedBox(height: AppSpacing.xxxl),
                  ],
                ),
              ),
            ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool isDanger;

  const _SettingsTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isDanger = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.mdAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isDanger ? AppColors.error.withValues(alpha: 0.03) : Colors.white,
          borderRadius: AppRadius.mdAll,
          border: Border.all(
            color: isDanger
                ? AppColors.error.withValues(alpha: 0.2)
                : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w600,
                    color: isDanger ? AppColors.error : AppColors.textPrimary,
                  )),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppColors.textTertiary)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: AppColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
