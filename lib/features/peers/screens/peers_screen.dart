import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/group_dao.dart';
import '../../../data/local/dao/group_member_dao.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/group_member_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../groups/screens/create_group_screen.dart';
import '../../groups/screens/groups_overview_tab.dart';
import '../../shared/screens/offline_video_player_screen.dart';
import '../../shared/widgets/guest_auth_required_view.dart';

class PeersScreen extends StatefulWidget {
  const PeersScreen({super.key});

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  final _dao = MessageDao();

  bool _loading = true;
  List<AcceptedPeerCollaboration> _collaborators = const [];
  List<GroupMemberModel> _pendingGroupInvites = const [];
  final Set<String> _respondingInviteIds = <String>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _collaborators = const [];
        _pendingGroupInvites = const [];
        _loading = false;
      });
      return;
    }

    final results = await Future.wait([
      _dao.getAcceptedCollaborators(userId: currentUserId),
      sl<GroupMemberDao>().getPendingInvitesForUser(currentUserId),
    ]);

    final accepted = results[0] as List<AcceptedPeerCollaboration>;
    final pendingInvites = results[1] as List<GroupMemberModel>;
    if (!mounted) return;
    setState(() {
      _collaborators = accepted;
      _pendingGroupInvites = pendingInvites;
      _loading = false;
    });
  }

  Future<void> _respondToGroupInvite(GroupMemberModel invite, bool accept) async {
    if (_respondingInviteIds.contains(invite.id)) return;
    setState(() => _respondingInviteIds.add(invite.id));

    try {
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

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            accept
                ? 'Invite accepted. You are now a group member.'
                : 'Invite declined.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not update invite: $e'),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _respondingInviteIds.remove(invite.id));
      }
    }
  }

  Future<void> _openCreateGroup() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CreateGroupScreen()),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final isGuest = sl<AuthCubit>().currentUser == null;

    if (isGuest) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            'Peers',
            style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
          ),
        ),
        body: const GuestAuthRequiredView(
          icon: Icons.group_off_rounded,
          title: 'Sign in to access Peers',
          subtitle:
              'Authentication is required to view collaborators, respond to requests, and manage groups.',
          fromRoute: RouteNames.peers,
        ),
      );
    }

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
      appBar: AppBar(
        title: Text(
          'Peers',
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _openCreateGroup,
            icon: const Icon(Icons.group_add_rounded),
            tooltip: 'Create group',
          ),
        ],
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Collaborators'),
            Tab(text: 'Groups'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          RefreshIndicator(
            color: AppColors.primary,
            onRefresh: _load,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: [
                if (_pendingGroupInvites.isNotEmpty) ...[
                  Text(
                    'Group Invites',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._pendingGroupInvites.map(
                    (invite) => _PendingGroupInviteCard(
                      invite: invite,
                      isLoading: _respondingInviteIds.contains(invite.id),
                      onDecline: () => _respondToGroupInvite(invite, false),
                      onAccept: () => _respondToGroupInvite(invite, true),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                if (_collaborators.isEmpty) ...[
                  const SizedBox(height: 40),
                  const Icon(
                    Icons.group_off_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No accepted collaborators yet',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Once a collaboration request is accepted, the collaborator and the agreed project will appear here.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: AppColors.textSecondaryLight,
                    ),
                  ),
                ] else ...[
                  _PeersSummary(count: _collaborators.length),
                  const SizedBox(height: 16),
                  ..._collaborators.map(
                    (item) => _PeerCollaborationCard(item: item),
                  ),
                ],
              ],
            ),
          ),
          GroupsOverviewTab(onChanged: _load),
        ],
      ),
    ),
    );
  }
}

class _PendingGroupInviteCard extends StatelessWidget {
  final GroupMemberModel invite;
  final bool isLoading;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _PendingGroupInviteCard({
    required this.invite,
    required this.isLoading,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
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
                  onPressed: isLoading ? null : onDecline,
                  child: const Text('Decline'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: isLoading ? null : onAccept,
                  child: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Accept'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PeersSummary extends StatelessWidget {
  final int count;

  const _PeersSummary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1152D4), Color(0xFF3B82F6)],
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
            child: const Icon(Icons.groups_2_rounded, color: Colors.white),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count active peer${count == 1 ? '' : 's'}',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Accepted collaborations with direct project context and quick actions.',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.35,
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

class _PeerCollaborationCard extends StatelessWidget {
  final AcceptedPeerCollaboration item;

  const _PeerCollaborationCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final statusColor = item.peerRole == 'lecturer'
        ? AppColors.roleLecturer
        : item.peerRole == 'admin' || item.peerRole == 'super_admin'
            ? AppColors.roleAdmin
            : AppColors.primary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: AppColors.surface(context),
        borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
        border: Border.all(color: AppColors.border(context)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: item.peerPhotoUrl != null
                      ? CachedNetworkImageProvider(item.peerPhotoUrl!)
                      : null,
                  child: item.peerPhotoUrl == null
                      ? Text(
                          item.peerName.isNotEmpty ? item.peerName[0].toUpperCase() : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.peerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.plusJakartaSans(fontSize: 15, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          _MiniBadge(
                            label: _roleLabel(item.peerRole),
                            color: statusColor,
                          ),
                          const _MiniBadge(
                            label: 'Accepted',
                            color: AppColors.success,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatRelative(item.acceptedAt),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          _ProjectPreview(item: item),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Text(
              item.postTitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(fontSize: 16, fontWeight: FontWeight.w700),
            ),
          ),
          if ((item.postCategory ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Text(
                item.postCategory!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ),
          if (item.message.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                item.message,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13,
                  color: AppColors.textSecondaryLight,
                  height: 1.4,
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: item.postId == null
                        ? null
                        : () => context.push('/project/${item.postId}'),
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text(
                      'Project',
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      softWrap: false,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: item.peerId.isEmpty
                        ? null
                        : () => context.push(
                              RouteNames.chatDetail.replaceFirst(':threadId', item.peerId),
                              extra: {
                                'peerName': item.peerName,
                                'peerPhotoUrl': item.peerPhotoUrl,
                                'isPeerLecturer': item.peerRole == 'lecturer',
                              },
                            ),
                    icon: const Icon(Icons.chat_bubble_outline_rounded, size: 18),
                      label: const Text(
                        'Message',
                        maxLines: 1,
                        overflow: TextOverflow.fade,
                        softWrap: false,
                      ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton(
                  onPressed: item.peerId.isEmpty
                      ? null
                      : () => context.push(RouteNames.profile.replaceFirst(':userId', item.peerId)),
                  icon: const Icon(Icons.arrow_forward_rounded),
                  tooltip: 'Open peer profile',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectPreview extends StatelessWidget {
  final AcceptedPeerCollaboration item;

  const _ProjectPreview({required this.item});

  @override
  Widget build(BuildContext context) {
    final previewUrl = item.postMediaUrls.isNotEmpty ? item.postMediaUrls.first : null;
    final isVideo = previewUrl != null && isVideoMediaPath(previewUrl);

    Widget child;
    if (previewUrl == null) {
      child = const _ProjectPreviewFallback();
    } else if (isVideo) {
      child = Stack(
        fit: StackFit.expand,
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF0F172A), Color(0xFF1E3A8A)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          const Center(
            child: Icon(
              Icons.play_circle_fill_rounded,
              size: 56,
              color: Colors.white,
            ),
          ),
        ],
      );
    } else if (isLocalMediaPath(previewUrl)) {
      child = Image.file(
        File(previewUrl),
        fit: BoxFit.cover,
        width: double.infinity,
        errorBuilder: (_, __, ___) => const _ProjectPreviewFallback(),
      );
    } else {
      child = CachedNetworkImage(
        imageUrl: previewUrl,
        fit: BoxFit.cover,
        width: double.infinity,
        errorWidget: (_, __, ___) => const _ProjectPreviewFallback(),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            color: AppColors.primaryTint10,
            child: InkWell(
              onTap: () {
                if (previewUrl == null) {
                  if (item.postId != null) {
                    context.push('/project/${item.postId}');
                  }
                  return;
                }

                if (isVideo) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => OfflineVideoPlayerScreen(
                        source: previewUrl,
                        title: item.postTitle,
                      ),
                    ),
                  );
                  return;
                }

                if (item.postId != null) {
                  context.push('/project/${item.postId}');
                }
              },
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectPreviewFallback extends StatelessWidget {
  const _ProjectPreviewFallback();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.primaryTint10,
      child: const Center(
        child: Icon(
          Icons.perm_media_rounded,
          size: 42,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _MiniBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniBadge({required this.label, required this.color});

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

String _roleLabel(String role) {
  switch (role) {
    case 'lecturer':
    case 'staff':
      return 'Lecturer';
    case 'admin':
    case 'super_admin':
      return 'Admin';
    default:
      return 'Student';
  }
}

String _formatRelative(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);
  if (diff.inDays >= 1) return '${diff.inDays}d';
  if (diff.inHours >= 1) return '${diff.inHours}h';
  if (diff.inMinutes >= 1) return '${diff.inMinutes}m';
  return 'now';
}
