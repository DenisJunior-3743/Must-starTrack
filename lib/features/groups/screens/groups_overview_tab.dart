import 'dart:async';

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
    this.topInset = 0,
  });

  final Future<void> Function() onChanged;
  final double topInset;

  @override
  State<GroupsOverviewTab> createState() => _GroupsOverviewTabState();
}

class _GroupsOverviewTabState extends State<GroupsOverviewTab>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  static const Duration _remoteRefreshCooldown = Duration(minutes: 2);

  bool _loading = true;
  bool _initialized = false;
  bool _remoteRefreshing = false;
  DateTime? _lastRemoteRefreshAt;
  List<GroupModel> _groups = const [];
  List<GroupMemberModel> _pendingInvites = const [];
  AnimationController? _pulseController;
  Animation<double>? _pulseScale;
  Animation<double>? _pulseHaloScale;
  Animation<double>? _pulseHaloOpacity;

  @override
  bool get wantKeepAlive => true;

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;

  void _notifyParentChanged() {
    final future = widget.onChanged();
    future.catchError((_) {});
  }

  @override
  void initState() {
    super.initState();
    _ensurePulseAnimation();
    _load();
  }

  void _ensurePulseAnimation() {
    if (_pulseController != null && _pulseScale != null) return;

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _pulseController = controller;
    _pulseScale = Tween<double>(begin: 0.92, end: 1.07).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
    _pulseHaloScale = Tween<double>(begin: 0.9, end: 1.25).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );
    _pulseHaloOpacity = Tween<double>(begin: 0.28, end: 0.08).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _ensurePulseAnimation();
  }

  @override
  void dispose() {
    _pulseController?.dispose();
    super.dispose();
  }

  Future<(List<GroupModel>, List<GroupMemberModel>)> _readLocalData(
      String userId) async {
    final groupDao = sl<GroupDao>();
    final memberDao = sl<GroupMemberDao>();
    final results = await Future.wait([
      groupDao.getGroupsForUser(userId),
      memberDao.getPendingInvitesForUser(userId),
    ]);

    return (
      results[0] as List<GroupModel>,
      results[1] as List<GroupMemberModel>,
    );
  }

  bool _shouldRefreshRemote() {
    if (_remoteRefreshing) return false;
    if (_lastRemoteRefreshAt == null) return true;
    return DateTime.now().difference(_lastRemoteRefreshAt!) >=
        _remoteRefreshCooldown;
  }

  Future<void> _refreshRemoteThenLocal(String userId) async {
    if (_remoteRefreshing) return;
    _remoteRefreshing = true;

    final syncService = sl<SyncService>();
    try {
      await syncService.processPendingSync();
      await syncService.syncRemoteToLocal(
        postLimit: 60,
        suppressNotificationAlerts: true,
      );
      _lastRemoteRefreshAt = DateTime.now();

      final local = await _readLocalData(userId);
      if (!mounted || _currentUserId != userId) return;
      setState(() {
        _groups = local.$1;
        _pendingInvites = local.$2;
      });
    } catch (error) {
      debugPrint('[GroupsOverview] Remote refresh failed: $error');
    } finally {
      _remoteRefreshing = false;
    }
  }

  Future<void> _load({bool forceRemoteRefresh = false}) async {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _groups = const [];
        _pendingInvites = const [];
        _loading = false;
        _initialized = true;
      });
      return;
    }

    // Show loading spinner only on first entry; later loads keep UI responsive.
    if (!_initialized && mounted) {
      setState(() => _loading = true);
    }

    // Fast path: read and render local snapshot first.
    final local = await _readLocalData(userId);

    if (!mounted) return;
    setState(() {
      _groups = local.$1;
      _pendingInvites = local.$2;
      _loading = false;
      _initialized = true;
    });

    if (forceRemoteRefresh || _shouldRefreshRemote()) {
      _refreshRemoteThenLocal(userId);
    }
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
    if (accept) {
      await syncService.refreshGroupWorkspace(
        groupId: invite.groupId,
        currentUid: invite.userId,
      );
    }
    await _load(forceRemoteRefresh: true);
    _notifyParentChanged();
  }

  Future<void> _openCreateGroup() async {
    final created = await Navigator.of(context).push<GroupModel>(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    if (created != null) {
      // Wait for the pop animation frame to finish before setState.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      _notifyParentChanged();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => GroupDetailScreen(groupId: created.id)),
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      await _load(forceRemoteRefresh: true);
      if (!mounted) return;
      _notifyParentChanged();
    }
  }

  Future<void> _openGroup(GroupModel group) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => GroupDetailScreen(groupId: group.id)),
    );
    // Wait for the pop animation frame to finish before calling setState.
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    await _load(forceRemoteRefresh: true);
    if (!mounted) return;
    _notifyParentChanged();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final groups = List<GroupModel>.of(_groups)
      ..removeWhere((group) => group.id.trim().isEmpty);
    final pendingInvites = List<GroupMemberModel>.of(_pendingInvites)
      ..removeWhere(
        (invite) =>
            invite.id.trim().isEmpty ||
            invite.groupId.trim().isEmpty ||
            invite.userId.trim().isEmpty,
      );

    if (_loading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: widget.topInset + 100),
          const Center(child: CircularProgressIndicator()),
        ],
      );
    }

    final totalProjects =
        groups.fold<int>(0, (sum, group) => sum + group.visiblePostCount);

    return DefaultTabController(
      length: 2,
      initialIndex: 0,
      child: Column(
        children: [
          SizedBox(height: widget.topInset),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF1152D4), Color(0xFF3B82F6)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF1152D4).withValues(alpha: 0.30),
                        blurRadius: 18,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(AppDimensions.radiusMd),
                        ),
                        child: const Icon(Icons.groups_rounded,
                            color: Colors.white),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${groups.length} active group${groups.length == 1 ? '' : 's'}',
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
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                _InfoPill(
                                  label:
                                      '${pendingInvites.length} pending invite${pendingInvites.length == 1 ? '' : 's'}',
                                ),
                                _InfoPill(label: '$totalProjects projects'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  right: -8,
                  top: -10,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      FadeTransition(
                        opacity:
                            _pulseHaloOpacity ?? const AlwaysStoppedAnimation(0),
                        child: ScaleTransition(
                          scale:
                              _pulseHaloScale ?? const AlwaysStoppedAnimation(1),
                          child: Container(
                            width: 52,
                            height: 52,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.45),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      ScaleTransition(
                        scale: _pulseScale ?? const AlwaysStoppedAnimation(1),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: _openCreateGroup,
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusFull),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: const Color(0xFF1152D4),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF1152D4)
                                        .withValues(alpha: 0.35),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.add_rounded,
                                color: Color(0xFF1152D4),
                                size: 22,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface(context),
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                border: Border.all(color: AppColors.border(context)),
              ),
              child: TabBar(
                labelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
                unselectedLabelStyle: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                indicator: BoxDecoration(
                  color: AppColors.primaryTint10,
                  borderRadius:
                      BorderRadius.circular(AppDimensions.radiusFull - 2),
                ),
                tabs: [
                  const Tab(text: 'My Groups'),
                  Tab(
                    text: pendingInvites.isEmpty
                        ? 'Pending Invites'
                        : 'Pending (${pendingInvites.length})',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: TabBarView(
              children: [
                RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await _load(forceRemoteRefresh: true);
                    if (!mounted) return;
                    _notifyParentChanged();
                  },
                  child: groups.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          children: [
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
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: groups.length,
                          itemBuilder: (context, index) {
                            final group = groups[index];
                            final initial = group.name.trim().isNotEmpty
                                ? group.name.trim().substring(0, 1).toUpperCase()
                                : '?';
                            return Card(
                              key: ValueKey<String>('group_${group.id}_$index'),
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                leading: CircleAvatar(
                                  backgroundColor:
                                      AppColors.primary.withValues(alpha: 0.14),
                                  child: Text(
                                    initial,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  group.name,
                                  style: GoogleFonts.plusJakartaSans(
                                      fontWeight: FontWeight.w700),
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
                                trailing: const Icon(
                                    Icons.arrow_forward_ios_rounded,
                                    size: 16),
                                onTap: () => _openGroup(group),
                              ),
                            );
                          },
                        ),
                ),
                RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    await _load(forceRemoteRefresh: true);
                    if (!mounted) return;
                    _notifyParentChanged();
                  },
                  child: pendingInvites.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          children: [
                            Card(
                              child: Padding(
                                padding: const EdgeInsets.all(18),
                                child: Text(
                                  'No pending invites right now.',
                                  style: GoogleFonts.plusJakartaSans(
                                    color: AppColors.textSecondaryLight,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 120),
                          itemCount: pendingInvites.length,
                          itemBuilder: (context, index) {
                            final invite = pendingInvites[index];
                            return Card(
                              key: ValueKey<String>(
                                  'group_invite_${invite.id}_$index'),
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
                                        Expanded(
                                          child: OutlinedButton(
                                            style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 34),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              textStyle:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            onPressed: () =>
                                                _respondToInvite(invite, false),
                                            child: const Text('Decline'),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: FilledButton(
                                            style: FilledButton.styleFrom(
                                              minimumSize: const Size(0, 34),
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      vertical: 8),
                                              visualDensity:
                                                  VisualDensity.compact,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              textStyle:
                                                  GoogleFonts.plusJakartaSans(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            onPressed: () =>
                                                _respondToInvite(invite, true),
                                            child: const Text('Accept'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoPill extends StatelessWidget {
  final String label;

  const _InfoPill({required this.label});

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
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
      ),
    );
  }
}
