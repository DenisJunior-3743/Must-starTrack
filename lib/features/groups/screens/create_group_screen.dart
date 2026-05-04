import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/group_dao.dart';
import '../../../data/local/dao/group_member_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/group_member_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({
    super.key,
    this.existingGroup,
  });

  final GroupModel? existingGroup;

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _avatarCtrl = TextEditingController();
  final _uuid = const Uuid();

  bool _saving = false;
  bool _loadingUsers = true;
  String _searchQuery = '';
  List<UserModel> _users = const [];
  Set<String> _peerIds = <String>{};
  final Set<String> _selectedUserIds = <String>{};

  bool get _isEditing => widget.existingGroup != null;

  @override
  void initState() {
    super.initState();
    final group = widget.existingGroup;
    if (group != null) {
      _nameCtrl.text = group.name;
      _descriptionCtrl.text = group.description ?? '';
      _avatarCtrl.text = group.avatarUrl ?? '';
      _loadingUsers = false;
    } else {
      _loadUsers();
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descriptionCtrl.dispose();
    _avatarCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadUsers() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      setState(() => _loadingUsers = false);
      return;
    }

    final userDao = sl<UserDao>();
    final messageDao = sl<MessageDao>();
    final allUsers = await userDao.getAllUsers(
      includeSuspended: false,
      pageSize: 400,
    );
    final peers = await messageDao.getAcceptedCollaborators(userId: currentUserId);
    final peerIds = peers.map((peer) => peer.peerId).where((id) => id.isNotEmpty).toSet();

    if (!mounted) return;
    setState(() {
      _peerIds = peerIds;
      _users = allUsers
          .where((user) =>
              user.id != currentUserId &&
              !user.isSuspended &&
              !user.isBanned)
          .toList()
        ..sort((left, right) {
          final leftPriority = _peerIds.contains(left.id) ? 0 : 1;
          final rightPriority = _peerIds.contains(right.id) ? 0 : 1;
          if (leftPriority != rightPriority) {
            return leftPriority.compareTo(rightPriority);
          }
          final leftName = (left.displayName ?? left.email).toLowerCase();
          final rightName = (right.displayName ?? right.email).toLowerCase();
          return leftName.compareTo(rightName);
        });
      _loadingUsers = false;
    });
  }

  List<UserModel> get _filteredUsers {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return _users;
    return _users.where((user) {
      final haystack = [
        user.displayName ?? '',
        user.email,
        user.profile?.faculty ?? '',
        user.profile?.courseName ?? '',
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isEditing && _selectedUserIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one member to invite.')),
      );
      return;
    }

    final currentUser = sl<AuthCubit>().currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sign in to create a group.')),
      );
      return;
    }

    setState(() => _saving = true);
    final now = DateTime.now();
    final groupDao = sl<GroupDao>();
    final groupMemberDao = sl<GroupMemberDao>();
    final syncQueue = sl<SyncQueueDao>();
    final syncService = sl<SyncService>();

    try {
      if (_isEditing) {
        final updated = widget.existingGroup!.copyWith(
          name: _nameCtrl.text.trim(),
          description: _descriptionCtrl.text.trim().isEmpty
              ? null
              : _descriptionCtrl.text.trim(),
          avatarUrl:
              _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
          updatedAt: now,
        );
        await groupDao.upsertGroup(updated);
        await syncQueue.enqueue(
          operation: 'update',
          entity: 'groups',
          entityId: updated.id,
          payload: updated.toMap(),
        );
        await syncService.processPendingSync();
        if (!mounted) return;
        Navigator.of(context).pop(updated);
        return;
      }

      final groupId = _uuid.v4();
      final group = GroupModel(
        id: groupId,
        name: _nameCtrl.text.trim(),
        description: _descriptionCtrl.text.trim().isEmpty
            ? null
            : _descriptionCtrl.text.trim(),
        avatarUrl: _avatarCtrl.text.trim().isEmpty ? null : _avatarCtrl.text.trim(),
        creatorId: currentUser.id,
        creatorName: currentUser.displayName ?? currentUser.email,
        memberCount: 1,
        createdAt: now,
        updatedAt: now,
      );

      final ownerMembership = GroupMemberModel(
        id: '${groupId}_${currentUser.id}',
        groupId: groupId,
        groupName: group.name,
        userId: currentUser.id,
        userName: currentUser.displayName ?? currentUser.email,
        userPhotoUrl: currentUser.photoUrl,
        role: 'owner',
        status: 'active',
        invitedBy: currentUser.id,
        invitedByName: currentUser.displayName ?? currentUser.email,
        joinedAt: now,
        createdAt: now,
        updatedAt: now,
      );

      final inviteMemberships = _users
          .where((user) => _selectedUserIds.contains(user.id))
          .map(
            (user) => GroupMemberModel(
              id: '${groupId}_${user.id}',
              groupId: groupId,
              groupName: group.name,
              userId: user.id,
              userName: user.displayName ?? user.email,
              userPhotoUrl: user.photoUrl,
              role: 'member',
              status: 'pending',
              invitedBy: currentUser.id,
              invitedByName: currentUser.displayName ?? currentUser.email,
              createdAt: now,
              updatedAt: now,
            ),
          )
          .toList();

      await groupDao.upsertGroup(group);
      await groupMemberDao.upsertMembers([ownerMembership, ...inviteMemberships]);

      await syncQueue.enqueue(
        operation: 'create',
        entity: 'groups',
        entityId: group.id,
        payload: group.toMap(),
      );
      for (final membership in [ownerMembership, ...inviteMemberships]) {
        await syncQueue.enqueue(
          operation: 'create',
          entity: 'group_members',
          entityId: membership.id,
          payload: membership.toMap(),
        );
      }

      await syncService.processPendingSync();
      if (!mounted) return;
      Navigator.of(context).pop(group);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save group: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  InputDecoration _inputDecoration({
    required bool isDark,
    required String label,
    String? hint,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      filled: true,
      fillColor: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.92),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.16)
              : AppColors.primary.withValues(alpha: 0.14),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(
          color: isDark
              ? Colors.white.withValues(alpha: 0.38)
              : AppColors.primary.withValues(alpha: 0.45),
          width: 1.2,
        ),
      ),
    );
  }

  BoxDecoration _cardDecoration(bool isDark) {
    return BoxDecoration(
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.white.withValues(alpha: 0.84),
      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
      border: Border.all(
        color: isDark
            ? Colors.white.withValues(alpha: 0.14)
            : AppColors.primary.withValues(alpha: 0.12),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = _isEditing ? 'Edit Group' : 'Create Group';
    final subtitle = _isEditing
        ? 'Refine your group details to keep everyone aligned.'
        : 'Build your team space and invite members in one clean flow.';

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          title,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? const [Color(0xFF0B1222), Color(0xFF111D36)]
                : const [Color(0xFFF8FBFF), Color(0xFFECF3FF)],
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -72,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -92,
              left: -86,
              child: _GlowBlob(size: 250, color: Color(0x221152D4)),
            ),
            Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecoration(isDark),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          subtitle,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 13,
                            color: AppColors.textSecondaryLight,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecoration(isDark),
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameCtrl,
                          decoration: _inputDecoration(
                            isDark: isDark,
                            label: 'Group Name',
                            hint: 'e.g. BSE Final Year Innovators',
                          ),
                          validator: (value) {
                            final text = value?.trim() ?? '';
                            if (text.isEmpty) return 'Group name is required.';
                            if (text.length < 3) {
                              return 'Use at least 3 characters.';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _descriptionCtrl,
                          maxLines: 4,
                          decoration: _inputDecoration(
                            isDark: isDark,
                            label: 'Description',
                            hint: 'What is this team building or exploring?',
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _avatarCtrl,
                          decoration: _inputDecoration(
                            isDark: isDark,
                            label: 'Group Avatar URL',
                            hint: 'Optional image URL for the group profile',
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isEditing) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: _cardDecoration(isDark),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Invite Members',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Suggested peers appear first, but you can invite any registered user in the application.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              color: AppColors.textSecondaryLight,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            onChanged: (value) {
                              setState(() => _searchQuery = value);
                            },
                            decoration: _inputDecoration(
                              isDark: isDark,
                              label: 'Search Members',
                              hint: 'Name, email, course, or faculty',
                              prefixIcon: const Icon(Icons.search_rounded),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_loadingUsers)
                            const Padding(
                              padding: EdgeInsets.all(24),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else if (_filteredUsers.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Text(
                                'No users match your search.',
                                style: GoogleFonts.plusJakartaSans(
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                            )
                          else
                            ..._filteredUsers.map((user) {
                              final selected =
                                  _selectedUserIds.contains(user.id);
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: selected
                                      ? AppColors.primaryTint10
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: selected
                                        ? AppColors.primary
                                            .withValues(alpha: 0.34)
                                        : AppColors.borderLight,
                                  ),
                                ),
                                child: CheckboxListTile(
                                  value: selected,
                                  activeColor: AppColors.primary,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  controlAffinity:
                                      ListTileControlAffinity.trailing,
                                  title: Text(
                                    user.displayName ?? user.email,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  subtitle: Text(
                                    [
                                      user.email,
                                      if ((user.profile?.faculty ?? '')
                                          .isNotEmpty)
                                        user.profile!.faculty!,
                                      if (_peerIds.contains(user.id))
                                        'Suggested peer',
                                    ].join(' • '),
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: AppColors.textSecondaryLight,
                                    ),
                                  ),
                                  onChanged: (_) {
                                    setState(() {
                                      if (selected) {
                                        _selectedUserIds.remove(user.id);
                                      } else {
                                        _selectedUserIds.add(user.id);
                                      }
                                    });
                                  },
                                ),
                              );
                            }),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              elevation: 0,
              textStyle: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Icon(_isEditing ? Icons.save_rounded : Icons.group_add_rounded),
            label: Text(_isEditing ? 'Save Group' : 'Create Group'),
          ),
        ),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowBlob({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: color,
              blurRadius: 80,
              spreadRadius: 25,
            ),
          ],
        ),
      ),
    );
  }
}
