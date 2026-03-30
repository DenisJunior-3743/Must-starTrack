import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/group_dao.dart';
import '../../../data/local/dao/group_member_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/group_member_model.dart';
import '../../../data/models/group_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import 'create_group_screen.dart';
import 'group_detail_screen.dart';

class GroupsOverviewTab extends StatefulWidget {
  const GroupsOverviewTab({
    super.key,
    required this.onChanged,
  });

  final Future<void> Function() onChanged;

  @override
  State<GroupsOverviewTab> createState() => _GroupsOverviewTabState();
}

class _GroupsOverviewTabState extends State<GroupsOverviewTab> {
  bool _loading = true;
  List<GroupModel> _groups = const [];
  List<GroupMemberModel> _pendingInvites = const [];

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _pendingInvites = const [];
        _loading = false;
      });
      return;
    }

    final groupDao = sl<GroupDao>();
    final memberDao = sl<GroupMemberDao>();
    final results = await Future.wait([
      groupDao.getGroupsForUser(userId),
      memberDao.getPendingInvitesForUser(userId),
    ]);

    if (!mounted) return;
    setState(() {
      _groups = results[0] as List<GroupModel>;
      _pendingInvites = results[1] as List<GroupMemberModel>;
      _loading = false;
    });
  }

  Future<void> _respondToInvite(GroupMemberModel invite, bool accept) async {
    final memberDao = sl<GroupMemberDao>();
    final groupDao = sl<GroupDao>();
    final syncQueue = sl<SyncQueueDao>();
    final syncService = sl<SyncService>();

    await memberDao.updateMembershipStatus(
      groupId: invite.groupId,
      userId: invite.userId,
      status: accept ? 'active' : 'declined',
      joinedAt: accept ? DateTime.now() : null,
    );

    final updated = await memberDao.getMembership(
      groupId: invite.groupId,
      userId: invite.userId,
    );
    if (updated != null) {
      await syncQueue.enqueue(
        operation: 'update',
        entity: 'group_members',
        entityId: updated.id,
        payload: updated.toMap(),
      );
    }

    final count = await memberDao.countActiveMembers(invite.groupId);
    final group = await groupDao.getGroupById(invite.groupId);
    if (group != null) {
      final refreshed = group.copyWith(
        memberCount: count,
        updatedAt: DateTime.now(),
      );
      await groupDao.upsertGroup(refreshed);
      await syncQueue.enqueue(
        operation: 'update',
        entity: 'groups',
        entityId: refreshed.id,
        payload: refreshed.toMap(),
      );
    }

    await syncService.processPendingSync();
    await widget.onChanged();
    await _load();
  }

  Future<void> _openCreateGroup() async {
    final created = await Navigator.of(context).push<GroupModel>(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (created != null) {
      await widget.onChanged();
      await _load();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: created.id)),
      );
      await _load();
    }
  }

  Future<void> _openGroup(GroupModel group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
    );
    await widget.onChanged();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: () async {
        await widget.onChanged();
        await _load();
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF0B6B58), Color(0xFF16A34A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                  ),
                  child: const Icon(Icons.groups_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${_groups.length} active group${_groups.length == 1 ? '' : 's'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Create teams, accept invites, and publish group projects into the home feed.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.92),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.success,
                  ),
                  onPressed: _openCreateGroup,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Create'),
                ),
              ],
            ),
          ),
          if (_pendingInvites.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(
              'Pending Invites',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            ..._pendingInvites.map(
              (invite) => Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invite.groupName ?? 'Group Invite',
                        style: GoogleFonts.plusJakartaSans(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Invited by ${invite.invitedByName ?? 'a group manager'}',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          OutlinedButton(
                            onPressed: () => _respondToInvite(invite, false),
                            child: const Text('Decline'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton(
                            onPressed: () => _respondToInvite(invite, true),
                            child: const Text('Accept'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 18),
          Text(
            'Your Groups',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          if (_groups.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'You are not in any active group yet. Create one or accept an invite to get started.',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.textSecondaryLight,
                    height: 1.4,
                  ),
                ),
              ),
            )
          else
            ..._groups.map(
              (group) => Card(
                margin: const EdgeInsets.only(bottom: 12),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  leading: CircleAvatar(
                    backgroundColor: AppColors.success.withValues(alpha: 0.14),
                    child: Text(
                      group.name.substring(0, 1).toUpperCase(),
                      style: GoogleFonts.plusJakartaSans(
                        fontWeight: FontWeight.w800,
                        color: AppColors.success,
                      ),
                    ),
                  ),
                  title: Text(
                    group.name,
                    style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      '${group.memberCount} members • ${group.visiblePostCount} projects',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () => _openGroup(group),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
