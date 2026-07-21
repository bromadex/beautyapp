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
    _tabCtrl = TabController(length: 3, vsync: this);
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
          .select('id, full_name, email, phone, user_type, is_verified, is_banned, created_at, avatar_url')
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
    }

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      users = users.where((u) {
        final name = (u['full_name'] ?? '').toString().toLowerCase();
        final email = (u['email'] ?? '').toString().toLowerCase();
        final phone = (u['phone'] ?? '').toString().toLowerCase();
        return name.contains(q) || email.contains(q) || phone.contains(q);
      }).toList();
    }

    return users;
  }

  Future<void> _toggleBan(Map<String, dynamic> user) async {
    final isBanned = user['is_banned'] == true;
    final action = isBanned ? 'unban' : 'ban';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadius.xlAll),
        title: Text('${isBanned ? 'Unban' : 'Ban'} User?'),
        content: Text(
          isBanned
              ? 'This will restore access for ${user['full_name']}.'
              : 'This will block ${user['full_name']} from using the app.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: isBanned ? AppColors.success : AppColors.error,
            ),
            child: Text(isBanned ? 'Unban' : 'Ban'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await supabase
          .from('profiles')
          .update({'is_banned': !isBanned})
          .eq('id', user['id']);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('User ${action}ned successfully'),
          backgroundColor: isBanned ? AppColors.success : AppColors.warning,
        ),
      );
      _loadUsers();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }

  void _showUserDetail(Map<String, dynamic> user) {
    final name = user['full_name'] ?? 'Unknown';
    final email = user['email'] ?? '';
    final phone = user['phone'] ?? '';
    final type = user['user_type'] ?? '';
    final isVerified = user['is_verified'] == true;
    final isBanned = user['is_banned'] == true;
    final createdAt = DateTime.tryParse(user['created_at'] ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.5,
        maxChildSize: 0.8,
        builder: (_, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: AppSpacing.screenPadding,
          child: Column(
            children: [
              Container(
                width: 64,
                height: 64,
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
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _badge(type == 'provider' ? 'Provider' : 'Client', AppColors.secondary),
                  if (isVerified) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _badge('Verified', AppColors.success),
                  ],
                  if (isBanned) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _badge('Banned', AppColors.error),
                  ],
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
              _detailRow(Icons.email_outlined, 'Email', email),
              _detailRow(Icons.phone_outlined, 'Phone', phone.isNotEmpty ? phone : 'Not set'),
              if (createdAt != null)
                _detailRow(Icons.calendar_today_outlined, 'Joined', createdAt.toLocal().toString().substring(0, 10)),
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  if (type == 'provider')
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {
                          Navigator.pop(context);
                          context.push('/provider/${user['id']}');
                        },
                        icon: const Icon(Icons.person_outlined, size: 18),
                        label: const Text('View Profile'),
                      ),
                    ),
                  if (type == 'provider') const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.pop(context);
                        _toggleBan(user);
                      },
                      icon: Icon(isBanned ? Icons.check_circle_outline : Icons.block_rounded, size: 18),
                      label: Text(isBanned ? 'Unban' : 'Ban User'),
                      style: FilledButton.styleFrom(
                        backgroundColor: isBanned ? AppColors.success : AppColors.error,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xxl),
            ],
          ),
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Users'),
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: [
            Tab(text: 'All (${_allUsers.length})'),
            Tab(text: 'Providers (${_allUsers.where((u) => u['user_type'] == 'provider').length})'),
            Tab(text: 'Clients (${_allUsers.where((u) => u['user_type'] == 'client').length})'),
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
                      hintText: 'Search by name, email or phone...',
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
    final email = user['email'] ?? '';
    final type = user['user_type'] ?? '';
    final isVerified = user['is_verified'] == true;
    final isBanned = user['is_banned'] == true;

    return InkWell(
      onTap: () => _showUserDetail(user),
      borderRadius: AppRadius.lgAll,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: isBanned ? AppColors.error.withValues(alpha: 0.03) : Colors.white,
          borderRadius: AppRadius.lgAll,
          border: Border.all(
            color: isBanned ? AppColors.error.withValues(alpha: 0.2) : Colors.grey.shade200,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                gradient: isBanned ? null : AppColors.primaryGradient,
                color: isBanned ? AppColors.error.withValues(alpha: 0.1) : null,
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
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
                        child: Text(
                          name,
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
                    email,
                    style: const TextStyle(fontSize: 12, color: AppColors.textTertiary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _badge(
              type == 'provider' ? 'Provider' : 'Client',
              type == 'provider' ? AppColors.secondary : AppColors.info,
            ),
            if (isBanned) ...[
              const SizedBox(width: AppSpacing.xs),
              _badge('Banned', AppColors.error),
            ],
          ],
        ),
      ),
    );
  }
}
