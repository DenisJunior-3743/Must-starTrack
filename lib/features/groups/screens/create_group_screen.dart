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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Edit Group' : 'Create Group',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Group Name',
                hintText: 'e.g. BSE Final Year Innovators',
              ),
              validator: (value) {
                final text = value?.trim() ?? '';
                if (text.isEmpty) return 'Group name is required.';
                if (text.length < 3) return 'Use at least 3 characters.';
                return null;
              },
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _descriptionCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Description',
                hintText: 'What is this team building or exploring?',
              ),
            ),
            const SizedBox(height: 14),
            TextFormField(
              controller: _avatarCtrl,
              decoration: const InputDecoration(
                labelText: 'Group Avatar URL',
                hintText: 'Optional image URL for the group profile',
              ),
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.primaryTint10,
                  borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                ),
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
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                onChanged: (value) => setState(() => _searchQuery = value),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search by name, email, course, or faculty',
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
                  final selected = _selectedUserIds.contains(user.id);
                  return CheckboxListTile(
                    value: selected,
                    activeColor: AppColors.primary,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      user.displayName ?? user.email,
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    subtitle: Text(
                      [
                        user.email,
                        if ((user.profile?.faculty ?? '').isNotEmpty)
                          user.profile!.faculty!,
                        if (_peerIds.contains(user.id)) 'Suggested peer',
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
                  );
                }),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(_isEditing ? Icons.save_rounded : Icons.group_add_rounded),
            label: Text(_isEditing ? 'Save Group' : 'Create Group'),
          ),
        ),
      ),
    );
  }
}
