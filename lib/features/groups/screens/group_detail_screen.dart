import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/group_dao.dart';
import '../../../data/local/dao/group_member_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/group_member_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../feed/bloc/feed_cubit.dart';
import '../../feed/screens/create_post_screen.dart';
import 'create_group_screen.dart';

class GroupDetailScreen extends StatefulWidget {
  const GroupDetailScreen({
    super.key,
    required this.groupId,
  });

  final String groupId;

  @override
  State<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends State<GroupDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  bool _loading = true;
  GroupModel? _group;
  GroupMemberModel? _myMembership;
  List<GroupMemberModel> _members = const [];
  List<PostModel> _posts = const [];

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;
  bool get _canManage => _myMembership?.canManage == true;
  bool get _canUpload => _myMembership?.isActive == true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final groupDao = sl<GroupDao>();
    final memberDao = sl<GroupMemberDao>();
    final postDao = sl<PostDao>();
    final syncService = sl<SyncService>();
    final userId = _currentUserId;

    try {
      await syncService.processPendingSync();
      if (userId != null && userId.isNotEmpty) {
        await syncService.refreshGroupWorkspace(
          groupId: widget.groupId,
          currentUid: userId,
        );
      } else {
        await syncService.syncRemoteToLocal(
          postLimit: 120,
          suppressNotificationAlerts: true,
        );
      }
    } catch (error) {
      debugPrint(
        '[GroupDetail] Remote refresh failed for group=${widget.groupId}: $error',
      );
    }

    final group = await groupDao.getGroupById(widget.groupId);
    final members = await memberDao.getMembersForGroup(widget.groupId);
    final posts = await postDao.getFeedPage(
      pageSize: 80,
      filterGroupId: widget.groupId,
      currentUserId: userId,
    );
    final myMembership = userId == null
        ? null
        : await memberDao.getMembership(
            groupId: widget.groupId, userId: userId);

    if (!mounted) return;
    setState(() {
      _group = group;
      _members = members;
      _posts = posts;
      _myMembership = myMembership;
      _loading = false;
    });
  }

  Future<void> _refreshGroupCount() async {
    final group = _group;
    if (group == null) return;
    final groupDao = sl<GroupDao>();
    final memberDao = sl<GroupMemberDao>();
    final syncQueue = sl<SyncQueueDao>();
    final count = await memberDao.countActiveMembers(group.id);
    final updated = group.copyWith(
      memberCount: count,
      updatedAt: DateTime.now(),
    );
    await groupDao.upsertGroup(updated);
    await syncQueue.enqueue(
      operation: 'update',
      entity: 'groups',
      entityId: updated.id,
      payload: updated.toMap(),
    );
    _group = updated;
  }

  Future<void> _respondToInvite(bool accept) async {
    final userId = _currentUserId;
    final group = _group;
    if (userId == null || group == null) return;

    final memberDao = sl<GroupMemberDao>();
    final syncQueue = sl<SyncQueueDao>();
    final syncService = sl<SyncService>();
    final joinedAt = accept ? DateTime.now() : null;
    await memberDao.updateMembershipStatus(
      groupId: group.id,
      userId: userId,
      status: accept ? 'active' : 'declined',
      joinedAt: joinedAt,
    );
    final updatedMembership =
        await memberDao.getMembership(groupId: group.id, userId: userId);
    if (updatedMembership != null) {
      await syncQueue.enqueue(
        operation: 'update',
        entity: 'group_members',
        entityId: updatedMembership.id,
        payload: updatedMembership.toMap(),
      );
    }
    await _refreshGroupCount();
    await syncService.processPendingSync();
    if (accept) {
      await syncService.refreshGroupWorkspace(
        groupId: group.id,
        currentUid: userId,
      );
    }
    await _load();
  }

  Future<void> _openEditGroup() async {
    final group = _group;
    if (group == null) return;
    final updated = await Navigator.of(context).push<GroupModel>(
      MaterialPageRoute(
        builder: (_) => CreateGroupScreen(existingGroup: group),
      ),
    );
    if (updated != null) {
      await _load();
    }
  }

  Future<void> _openUploadProject() async {
    final group = _group;
    if (group == null) return;
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => sl<FeedCubit>(),
          child: CreatePostScreen(
            groupId: group.id,
            groupName: group.name,
            groupAvatarUrl: group.avatarUrl,
          ),
        ),
      ),
    );
    if (result == true) {
      await _load();
    }
  }

  Future<void> _dissolveGroup() async {
    final group = _group;
    if (group == null) return;
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Dissolve group?'),
            content: Text(
              '"${group.name}" will remain visible historically, but members will no longer collaborate under it.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Dissolve'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;

    final groupDao = sl<GroupDao>();
    final syncQueue = sl<SyncQueueDao>();
    final syncService = sl<SyncService>();
    await groupDao.dissolveGroup(group.id);
    await syncQueue.enqueue(
      operation: 'dissolve',
      entity: 'groups',
      entityId: group.id,
      payload: {'group_id': group.id},
    );
    await syncService.processPendingSync();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _openInviteDialog() async {
    final group = _group;
    final currentUser = sl<AuthCubit>().currentUser;
    if (group == null || currentUser == null) return;

    final userDao = sl<UserDao>();
    final memberDao = sl<GroupMemberDao>();
    final syncQueue = sl<SyncQueueDao>();
    final syncService = sl<SyncService>();
    final existingIds = _members.map((member) => member.userId).toSet();
    final allUsers = await userDao.getAllUsers(
      includeSuspended: false,
      pageSize: 400,
    );
    final candidates = allUsers
        .where((user) =>
            user.id != currentUser.id &&
            !existingIds.contains(user.id) &&
            !user.isSuspended &&
            !user.isBanned)
        .toList();

    if (!mounted) return;
    final selectedIds = <String>{};
    final picked = await showDialog<bool>(
      context: context,
      builder: (context) {
        var query = '';
        return StatefulBuilder(
          builder: (context, setModalState) {
            final filtered = candidates.where((user) {
              final haystack = [
                user.displayName ?? '',
                user.email,
                user.profile?.faculty ?? '',
                user.profile?.courseName ?? '',
              ].join(' ').toLowerCase();
              return haystack.contains(query);
            }).toList();

            return AlertDialog(
              insetPadding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
              ),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
              contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              title: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.group_add_rounded,
                      size: 18,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Invite Members',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Search and select users to send group invites.',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      onChanged: (value) =>
                          setModalState(() => query = value.toLowerCase()),
                      decoration: InputDecoration(
                        hintText: 'Search registered users',
                        hintStyle: GoogleFonts.plusJakartaSans(fontSize: 13),
                        prefixIcon: const Icon(Icons.search_rounded),
                        filled: true,
                        fillColor: AppColors.primaryTint10,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.16),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.16),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(
                            color: AppColors.primary.withValues(alpha: 0.42),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: filtered.map((user) {
                          final checked = selectedIds.contains(user.id);
                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              color: checked
                                  ? AppColors.primaryTint10
                                  : Colors.transparent,
                              border: Border.all(
                                color: checked
                                    ? AppColors.primary.withValues(alpha: 0.30)
                                    : AppColors.borderLight,
                              ),
                            ),
                            child: CheckboxListTile(
                              value: checked,
                              activeColor: const Color(0xFF10B981),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10,
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
                                user.email,
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 12,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                              onChanged: (_) {
                                setModalState(() {
                                  if (checked) {
                                    selectedIds.remove(user.id);
                                  } else {
                                    selectedIds.add(user.id);
                                  }
                                });
                              },
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Send Invites'),
                ),
              ],
            );
          },
        );
      },
    );

    if (picked != true || selectedIds.isEmpty) return;

    final now = DateTime.now();
    final memberships = candidates
        .where((user) => selectedIds.contains(user.id))
        .map(
          (user) => GroupMemberModel(
            id: '${group.id}_${user.id}',
            groupId: group.id,
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

    await memberDao.upsertMembers(memberships);
    for (final member in memberships) {
      await syncQueue.enqueue(
        operation: 'create',
        entity: 'group_members',
        entityId: member.id,
        payload: member.toMap(),
      );
    }
    await syncService.processPendingSync();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final group = _group;
    if (group == null) {
      return const Scaffold(
        body: Center(child: Text('Group not found.')),
      );
    }

    final activeMembers = _members.where((member) => member.isActive).toList();
    final pendingMembers =
        _members.where((member) => !member.isActive).toList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        title: Text(
          group.name,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          if (_canUpload)
            IconButton(
              onPressed: _openUploadProject,
              icon: const Icon(Icons.upload_file_rounded),
              tooltip: 'Upload group project',
            ),
          if (_canManage)
            IconButton(
              onPressed: _openInviteDialog,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              tooltip: 'Invite members',
            ),
          if (_canManage)
            IconButton(
              onPressed: _openEditGroup,
              icon: const Icon(Icons.edit_rounded),
              tooltip: 'Edit group',
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(62),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.86),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.16)
                      : AppColors.primary.withValues(alpha: 0.12),
                ),
              ),
              child: TabBar(
                controller: _tabController,
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                dividerColor: Colors.transparent,
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: const Color(0xFF10B981),
                  borderRadius: BorderRadius.circular(12),
                ),
                labelColor: Colors.white,
                unselectedLabelColor: AppColors.textSecondaryLight,
                tabs: const [
                  Tab(text: 'Projects'),
                  Tab(text: 'Members'),
                  Tab(text: 'Info'),
                ],
              ),
            ),
          ),
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
              top: -70,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -82,
              left: -88,
              child: _GlowBlob(size: 250, color: Color(0x221152D4)),
            ),
            Column(
              children: [
                if (_myMembership?.status == 'pending')
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppColors.warning.withValues(alpha: 0.40),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.mark_email_unread_rounded,
                            color: AppColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'You have a pending invite to join this group.',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.warning,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: () => _respondToInvite(false),
                          child: const Text('Decline'),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          height: 36,
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                            ),
                            onPressed: () => _respondToInvite(true),
                            child: const Text('Accept'),
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      RefreshIndicator(
                        onRefresh: _load,
                        child: _posts.isEmpty
                            ? ListView(
                                padding: const EdgeInsets.all(24),
                                children: [
                                  const SizedBox(height: 80),
                                  const Icon(Icons.folder_copy_outlined,
                                      size: 64, color: AppColors.primary),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No group projects yet',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    _canUpload
                                        ? 'Use the upload action to publish the first project for this group.'
                                        : 'Projects will appear here after active members publish them.',
                                    textAlign: TextAlign.center,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13,
                                      color: AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              )
                            : ListView(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 96),
                                children: _posts
                                    .map(
                                      (post) => Container(
                                        margin:
                                            const EdgeInsets.only(bottom: 12),
                                        decoration: BoxDecoration(
                                          color: isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.06)
                                              : Colors.white
                                                  .withValues(alpha: 0.86),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border: Border.all(
                                            color: isDark
                                                ? Colors.white.withValues(
                                                    alpha: 0.15)
                                                : AppColors.primary
                                                    .withValues(alpha: 0.10),
                                          ),
                                        ),
                                        child: ListTile(
                                          contentPadding:
                                              const EdgeInsets.all(14),
                                          title: Text(
                                            post.title,
                                            style:
                                                GoogleFonts.plusJakartaSans(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          subtitle: Padding(
                                            padding:
                                                const EdgeInsets.only(top: 8),
                                            child: Text(
                                              post.description ??
                                                  'No description provided.',
                                              maxLines: 3,
                                              overflow: TextOverflow.ellipsis,
                                              style:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                color: AppColors
                                                    .textSecondaryLight,
                                                height: 1.4,
                                              ),
                                            ),
                                          ),
                                          trailing: const Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 16,
                                          ),
                                          onTap: () => context.push(
                                            RouteNames.projectDetail
                                                .replaceFirst(
                                                    ':postId', post.id),
                                          ),
                                        ),
                                      ),
                                    )
                                    .toList(),
                              ),
                      ),
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        children: [
                          Text(
                            'Active Members (${activeMembers.length})',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 10),
                          ...activeMembers
                              .map((member) => _MemberTile(member: member)),
                          if (pendingMembers.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Text(
                              'Pending Invites (${pendingMembers.length})',
                              style: GoogleFonts.plusJakartaSans(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 10),
                            ...pendingMembers
                                .map((member) => _MemberTile(member: member)),
                          ],
                        ],
                      ),
                      ListView(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                        children: [
                          Container(
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [
                                  Color(0xFF0F4C81),
                                  Color(0xFF3B82F6),
                                ],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(
                                  AppDimensions.radiusLg),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  group.description ??
                                      'No group description added yet.',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.92),
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Wrap(
                                  spacing: 10,
                                  runSpacing: 10,
                                  children: [
                                    _StatPill(
                                        label:
                                            '${activeMembers.length} active members'),
                                    _StatPill(label: '${_posts.length} projects'),
                                    _StatPill(
                                        label: group.isDissolved
                                            ? 'Dissolved'
                                            : 'Active'),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          if (_canUpload)
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF10B981),
                                foregroundColor: Colors.white,
                              ),
                              onPressed: _openUploadProject,
                              icon: const Icon(Icons.upload_file_rounded),
                              label: const Text('Upload Group Project'),
                            ),
                          if (_canManage) ...[
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _openInviteDialog,
                              icon: const Icon(Icons.person_add_alt_1_rounded),
                              label: const Text('Invite Members'),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _openEditGroup,
                              icon: const Icon(Icons.edit_rounded),
                              label: const Text('Edit Group Profile'),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _dissolveGroup,
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                              ),
                              icon: const Icon(Icons.delete_outline_rounded),
                              label: const Text('Dissolve Group'),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({required this.member});

  final GroupMemberModel member;

  @override
  Widget build(BuildContext context) {
    final roleColor = member.role == 'owner'
        ? AppColors.primary
        : member.role == 'admin'
            ? AppColors.roleLecturer
            : AppColors.success;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: AppColors.primaryTint10,
          child: Text(
            (member.userName ?? '?').substring(0, 1).toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
            ),
          ),
        ),
        title: Text(
          member.userName ?? member.userId,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        subtitle: Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _RoleBadge(label: member.role.toUpperCase(), color: roleColor),
            _RoleBadge(
              label: member.status.toUpperCase(),
              color: member.isActive ? AppColors.success : AppColors.warning,
            ),
          ],
        ),
      ),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  const _RoleBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: Colors.white,
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
