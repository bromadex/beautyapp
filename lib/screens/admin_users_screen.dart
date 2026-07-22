import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../supabase_client.dart';
import '../theme.dart';

class AdminUsersScreen extends StatefulWidget {
  const AdminUsersScreen({super.key});

  @override
  State<AdminUsersScreen> createState() => _AdminUsersScreenState();
}

class _AdminUsersScreenState extends State<AdminUsersScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  bool _loading = true;
  List<Map<String, dynamic>> _allUsers = [];
  String _searchQuery = '';
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 4, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
    _checkAdminAndLoad();
  }

  Future<void> _checkAdminAndLoad() async {
    final userId = supabase.auth.currentUser?.id;
    if (userId == null) { if (mounted) context.go('/login'); return; }

    final adminRows = await supabase.from('admins').select().eq('user_id', userId);
    if ((adminRows as List).isEmpty) {
      if (mounted) { context.go('/home'); return; }
    }
    await _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _loading = true);
    try {
      final data = await supabase
          .from('profiles')
          .select('id, full_name, phone, user_type, is_verified, is_banned, is_deactivated, created_at')
          .order('created_at', ascending: false);
      if (mounted) {
        setState(() {
          _allUsers = List<Map<String, dynamic>>.from(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  List<Map<String, dynamic>> get _filteredUsers {
    final tabIndex = _tabCtrl.index;
    var users = _allUsers;

    if (tabIndex == 1) {
      users = users.where((u) => u['user_type'] == 'provider').toList();
    } else if (tabIndex == 2) {
      users = users.where((u) => u['user_type'] == 'client').toList();
    } else if (tabIndex == 3) {
      users = users.where((u) =>
        u['is_banned'] == true || u['is_deactivated'] == true).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      users = users.where((u) {
        final name = (u['full_name'] ?? '').toString().toLowerCase();
        final phone = (u['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || phone.contains(q);
      }).toList();
    }

    return users;
  }

  Future<void> _toggleBan(Map<String, dynamic> user) async {
    final isBanned = user['is_banned'] == true;
    final confirmed = await _confirmDialog(
      title: '${isBanned ? 'Unban' : 'Ban'} User?',
      message: isBanned
          ? 'This will restore access for ${user['full_name']}.'
          : 'This will block ${user['full_name']} from using the app.',
      confirmLabel: isBanned ? 'Unban' : 'Ban',
      confirmColor: isBanned ? AppColors.success : AppColors.error,
    );
    if (confirmed != true) return;

    try {
      await supabase.from('profiles').update({'is_banned': !isBanned}).eq('id', user['id']);
      _showSnack('User ${isBanned ? 'unbanned' : 'banned'} successfully',
          color: isBanned ? AppColors.success : AppColors.warning);
      _loadUsers();
    } catch (e) {
      _showSnack('Error: $e', color: AppColors.error);
    }
  }

  Future<void> _toggleFreeze(Map<String, dynamic> user) async {
    final isDeactivated = user['is_deactivated'] == true;
    final confirmed = await _confirmDialog(
      title: '${isDeactivated ? 'Unfreeze' : 'Freeze'} Account?',
      message: isDeactivated
          ? 'This will reactivate ${user['full_name']}\'s account.'
          : 'This will deactivate ${user['full_name']}\'s account. Their profile will be hidden from search.',
      confirmLabel: isDeactivated ? 'Unfreeze' : 'Freeze',
      confirmColor: isDeactivated ? AppColors.success : AppColors.info,
    );
    if (confirmed != true) return;

    try {
      await supabase.from('profiles').update({'is_deactivated': !isDeactivated}).eq('id', user['id']);
      _showSnack('Account ${isDeactivated ? 'unfrozen' : 'frozen'} successfully',
          color: isDeactivated ? AppColors.success : AppColors.info);
      _loadUsers();
    } catch (e) {
      _showSnack('Error: $e', color: AppColors.error);
    }
  }

  Future<void> _deleteUser(Map<String, dynamic> user) async {
    final confirmed = await _confirmDialog(
      title: 'Delete Account?',
      message: 'This will permanently delete ${user['full_name']}\'s account and ALL their data. This cannot be undone.',
      confirmLabel: 'Delete Forever',
      confirmColor: AppColors.error,
    );
    if (confirmed != true) return;

    // Second confirmation
    final secondConfirm = await _confirmDialog(
      title: 'Are you absolutely sure?',
      message: 'Type the user\'s name to confirm: ${user['full_name']}',
      confirmLabel: 'Delete',
      confirmColor: AppColors.error,
    );
    if (secondConfirm != true) return;

    try {
      final uid = user['id'];
      await supabase.rpc('admin_delete_user', params: {'target_user_id': uid});
      _showSnack('Account deleted', color: AppColors.textSecondary);
      _loadUsers();
    } catch (e) {
      _showSnack('Error: $e', color: AppColors.error);
    }
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.lgAll),
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  void _showSnack(String msg, {Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
      ),
    );
  }

  void _showUserDetail(Map<String, dynamic> user) {
    final name = user['full_name'] ?? 'Unknown';
    final phone = user['phone'] ?? '';
    final type = user['user_type'] ?? '';
    final isVerified = user['is_verified'] == true;
    final isBanned = user['is_banned'] == true;
    final isDeactivated = user['is_deactivated'] == true;
    final createdAt = DateTime.tryParse(user['created_at'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.55,
        maxChildSize: 0.85,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: AppSpacing.screenPadding,
          child: Column(
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Container(
                width: 64, height: 64,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(name, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 6, runSpacing: 4,
                alignment: WrapAlignment.center,
                children: [
                  _badge(type == 'provider' ? 'Provider' : 'Client', AppColors.secondary),
                  if (isVerified) _badge('Verified', AppColors.success),
                  if (isBanned) _badge('Banned', AppColors.error),
                  if (isDeactivated) _badge('Frozen', AppColors.info),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _detailRow(Icons.phone_outlined, 'Phone', phone.isNotEmpty ? phone : 'Not set'),
              if (createdAt != null)
                _detailRow(Icons.calendar_today_outlined, 'Joined', createdAt.toLocal().toString().substring(0, 10)),
              _detailRow(Icons.shield_outlined, 'Status',
                isBanned ? 'Banned' : isDeactivated ? 'Frozen' : 'Active'),
              const SizedBox(height: AppSpacing.xxl),

              // Action buttons
              if (type == 'provider')
                _actionButton(
                  icon: Icons.person_outlined,
                  label: 'View Public Profile',
                  color: AppColors.primary,
                  onTap: () {
                    Navigator.pop(context);
                    context.push('/provider/${user['id']}');
                  },
                ),
              const SizedBox(height: 8),
              _actionButton(
                icon: isBanned ? Icons.check_circle_outline : Icons.block_rounded,
                label: isBanned ? 'Unban User' : 'Ban User',
                color: isBanned ? AppColors.success : AppColors.error,
                onTap: () {
                  Navigator.pop(context);
                  _toggleBan(user);
                },
              ),
              const SizedBox(height: 8),
              _actionButton(
                icon: isDeactivated ? Icons.play_circle_outline : Icons.pause_circle_outline,
                label: isDeactivated ? 'Unfreeze Account' : 'Freeze Account',
                color: AppColors.info,
                onTap: () {
                  Navigator.pop(context);
                  _toggleFreeze(user);
                },
              ),
              const SizedBox(height: 8),
              _actionButton(
                icon: Icons.delete_forever_rounded,
                label: 'Delete Account',
                color: AppColors.error,
                isDanger: true,
                onTap: () {
                  Navigator.pop(context);
                  _deleteUser(user);
                },
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool isDanger = false,
  }) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: AppRadius.mdAll),
          backgroundColor: isDanger ? color.withValues(alpha: 0.04) : null,
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadius.smAll,
      ),
      child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppColors.textTertiary),
          const SizedBox(width: AppSpacing.md),
          Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textTertiary)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final users = _filteredUsers;
    final flaggedCount = _allUsers.where((u) =>
      u['is_banned'] == true || u['is_deactivated'] == true).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [
            Tab(text: 'All (${_allUsers.length})'),
            Tab(text: 'Providers (${_allUsers.where((u) => u['user_type'] == 'provider').length})'),
            Tab(text: 'Clients (${_allUsers.where((u) => u['user_type'] == 'client').length})'),
            Tab(text: 'Flagged ($flaggedCount)'),
          ],
        ),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: TextField(
                    controller: _searchCtrl,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Search by name or phone...',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _searchQuery = '');
                              },
                            )
                          : null,
                    ),
                  ),
                ),
                Expanded(
                  child: users.isEmpty
                      ? Center(
                          child: Text(
                            _searchQuery.isNotEmpty ? 'No users match your search' : 'No users found',
                            style: const TextStyle(color: AppColors.textTertiary),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                          itemCount: users.length,
                          separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                          itemBuilder: (_, i) => _buildUserCard(users[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildUserCard(Map<String, dynamic> user) {
    final name = user['full_name'] ?? 'Unknown';
    final phone = user['phone'] ?? '';
    final type = user['user_type'] ?? '';
    final isVerified = user['is_verified'] == true;
    final isBanned = user['is_banned'] == true;
    final isDeactivated = user['is_deactivated'] == true;

    return InkWell(
      onTap: () => _showUserDetail(user),
      borderRadius: AppRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isBanned
              ? AppColors.error.withValues(alpha: 0.03)
              : isDeactivated
                  ? AppColors.info.withValues(alpha: 0.03)
                  : Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isBanned
                ? AppColors.error.withValues(alpha: 0.2)
                : isDeactivated
                    ? AppColors.info.withValues(alpha: 0.2)
                    : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                gradient: isBanned ? null : AppColors.primaryGradient,
                color: isBanned ? AppColors.error.withValues(alpha: 0.1) : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16,
                    color: isBanned ? AppColors.error : Colors.white,
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(name,
                          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isVerified) ...[
                        const SizedBox(width: AppSpacing.xs),
                        const Icon(Icons.verified_rounded, color: AppColors.success, size: 14),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    phone.isNotEmpty ? phone : 'No phone',
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Wrap(
              spacing: 4,
              children: [
                _badge(
                  type == 'provider' ? 'Provider' : 'Client',
                  type == 'provider' ? AppColors.secondary : AppColors.info,
                ),
                if (isBanned) _badge('Banned', AppColors.error),
                if (isDeactivated && !isBanned) _badge('Frozen', AppColors.info),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
