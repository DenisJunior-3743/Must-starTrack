import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/user_model.dart';
import '../../auth/bloc/auth_cubit.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final _userDao = sl<UserDao>();
  final _activityDao = sl<ActivityLogDao>();
  bool _loading = true;
  String _roleFilter = 'all';
  bool _suspendedOnly = false;
  List<UserModel> _users = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final users = await _userDao.getAllUsers(
        role: _roleFilter == 'all' ? null : _roleFilter,
        includeSuspended: true,
        pageSize: 250,
      );
      if (!mounted) return;
      setState(() {
        _users = _suspendedOnly
            ? users.where((u) => u.isSuspended).toList()
            : users;
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _suspend(UserModel user) async {
    await _userDao.suspendUser(user.id);
    await _activityDao.logAction(
      userId: user.id,
      action: 'admin_suspended_user',
      entityType: 'users',
      entityId: user.id,
      metadata: {'source': 'user_management_screen'},
    );
    await _load();
  }

  Future<void> _ban(UserModel user) async {
    await _userDao.banUser(user.id);
    await _activityDao.logAction(
      userId: user.id,
      action: 'admin_banned_user',
      entityType: 'users',
      entityId: user.id,
      metadata: {'source': 'user_management_screen'},
    );
    await _load();
  }

  Future<void> _delete(UserModel user) async {
    await _userDao.deleteUser(user.id);
    await _activityDao.logAction(
      userId: user.id,
      action: 'admin_deleted_user',
      entityType: 'users',
      entityId: user.id,
      metadata: {'source': 'user_management_screen'},
    );
    await _load();
  }

  Future<void> _confirmDelete(UserModel user) async {
    final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete User'),
            content: Text('Delete ${user.displayName ?? user.email}? This cannot be undone.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!ok) return;
    await _delete(user);
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _roleFilter,
                    decoration: const InputDecoration(
                      labelText: 'Role',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('All roles')),
                      DropdownMenuItem(value: 'student', child: Text('Student')),
                      DropdownMenuItem(value: 'lecturer', child: Text('Lecturer')),
                      DropdownMenuItem(value: 'admin', child: Text('Admin')),
                      DropdownMenuItem(value: 'super_admin', child: Text('Super Admin')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _roleFilter = value);
                      _load();
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilterChip(
                  label: const Text('Suspended only'),
                  selected: _suspendedOnly,
                  onSelected: (v) {
                    setState(() => _suspendedOnly = v);
                    _load();
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: _users.length,
                    itemBuilder: (context, index) {
                      final user = _users[index];
                      final isSelf = user.id == currentUserId;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: AppColors.primaryTint10,
                            child: Text(
                              (user.displayName ?? user.email)[0].toUpperCase(),
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          title: Text(
                            user.displayName ?? user.email,
                            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            '${user.email}\nrole: ${user.role.name}'
                            '${user.isSuspended ? ' · suspended' : ''}'
                            '${user.isBanned ? ' · banned' : ''}',
                            style: GoogleFonts.plusJakartaSans(fontSize: 12),
                          ),
                          isThreeLine: true,
                          trailing: PopupMenuButton<String>(
                            enabled: !isSelf,
                            onSelected: (value) async {
                              if (value == 'suspend') {
                                await _suspend(user);
                              } else if (value == 'ban') {
                                await _ban(user);
                              } else if (value == 'delete') {
                                await _confirmDelete(user);
                              }
                            },
                            itemBuilder: (_) => const [
                              PopupMenuItem(value: 'suspend', child: Text('Suspend')),
                              PopupMenuItem(value: 'ban', child: Text('Ban')),
                              PopupMenuItem(value: 'delete', child: Text('Delete')),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
