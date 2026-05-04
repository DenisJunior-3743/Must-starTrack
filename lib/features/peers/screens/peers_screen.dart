import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/local/dao/message_dao.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../groups/screens/create_group_screen.dart';
import '../../groups/screens/groups_overview_tab.dart';
import '../../shared/widgets/guest_auth_required_view.dart';

class PeersScreen extends StatefulWidget {
  const PeersScreen({super.key});

  @override
  State<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends State<PeersScreen> {
  static const Duration _staleAfter = Duration(minutes: 2);
  static DateTime? _cacheLoadedAt;
  static String? _cacheUserId;
  static List<AcceptedPeerCollaboration> _cachedCollaborators = const [];

  final _dao = MessageDao();

  bool _loading = true;
  List<AcceptedPeerCollaboration> _collaborators = const [];

  @override
  void initState() {
    super.initState();
    _load(useCacheFirst: true);
  }

  Future<void> _load({
    bool useCacheFirst = false,
    bool silentRefresh = false,
  }) async {
    final currentUserId = sl<AuthCubit>().currentUser?.id;
    if (currentUserId == null || currentUserId.isEmpty) {
      _cacheUserId = null;
      _cacheLoadedAt = null;
      _cachedCollaborators = const [];
      if (!mounted) return;
      setState(() {
        _collaborators = const [];
        _loading = false;
      });
      return;
    }

    if (useCacheFirst &&
        _cacheUserId == currentUserId &&
        _cacheLoadedAt != null) {
      if (mounted) {
        setState(() {
          _collaborators = _cachedCollaborators;
          _loading = false;
        });
      }

      final age = DateTime.now().difference(_cacheLoadedAt!);
      if (age >= _staleAfter) {
        unawaited(_load(useCacheFirst: false, silentRefresh: true));
      }
      return;
    }

    if (!silentRefresh && mounted) {
      setState(() => _loading = true);
    }

    final accepted = await _dao.getAcceptedCollaborators(userId: currentUserId);

    _cacheUserId = currentUserId;
    _cacheLoadedAt = DateTime.now();
    _cachedCollaborators = accepted;
    if (!mounted) return;
    setState(() {
      _collaborators = accepted;
      _loading = false;
    });
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
    final collaborators = List<AcceptedPeerCollaboration>.of(_collaborators);

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final contentTopPadding = MediaQuery.of(context).padding.top +
        kToolbarHeight +
        kTextTabBarHeight +
        16;

    if (isGuest) {
      return Scaffold(
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
                top: -80,
                right: -70,
                child: _GlowBlob(size: 220, color: Color(0x332563EB)),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                      child: Row(
                        children: [
                          const SizedBox(width: 8),
                          Text(
                            'Peers',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.3,
                              color: isDark
                                  ? AppColors.textPrimaryDark
                                  : AppColors.textPrimaryLight,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Expanded(
                      child: GuestAuthRequiredView(
                        icon: Icons.group_off_rounded,
                        title: 'Sign in to access Peers',
                        subtitle:
                            'Authentication is required to view collaborators, respond to requests, and manage groups.',
                        fromRoute: RouteNames.peers,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_loading) {
      return Scaffold(
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
          child: const Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        extendBodyBehindAppBar: true,
        appBar: AppBar(
          backgroundColor: isDark
              ? const Color(0xFF0B1222).withValues(alpha: 0.92)
              : const Color(0xFFF8FBFF).withValues(alpha: 0.92),
          elevation: 0,
          scrolledUnderElevation: 0,
          title: Text(
            'Peers',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: isDark
                  ? AppColors.textPrimaryDark
                  : AppColors.textPrimaryLight,
            ),
          ),
          actions: [
            IconButton(
              onPressed: _openCreateGroup,
              icon: const Icon(Icons.group_add_rounded),
              tooltip: 'Create group',
            ),
          ],
          bottom: TabBar(
            labelStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
            unselectedLabelStyle: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w400,
            ),
            tabs: const [
              Tab(text: 'Collaborators'),
              Tab(text: 'Groups'),
            ],
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
                top: -80,
                right: -70,
                child: _GlowBlob(size: 220, color: Color(0x332563EB)),
              ),
              const Positioned(
                bottom: -90,
                left: -85,
                child: _GlowBlob(size: 260, color: Color(0x221152D4)),
              ),
              TabBarView(
                children: [
                  Column(
                    children: [
                      SizedBox(height: contentTopPadding),
                      if (collaborators.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                          child: _PeersSummary(count: collaborators.length),
                        ),
                      Expanded(
                        child: RefreshIndicator(
                          color: AppColors.primary,
                          onRefresh: _load,
                          child: collaborators.isEmpty
                              ? ListView(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 40, 16, 96),
                                  children: [
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
                                  ],
                                )
                              : ListView.builder(
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 0, 16, 96),
                                  itemCount: collaborators.length,
                                  itemBuilder: (context, index) {
                                    final item = collaborators[index];
                                    return KeyedSubtree(
                                      key: ValueKey<String>(
                                          'collab_${item.requestId}_$index'),
                                      child:
                                          _PeerCollaborationCard(item: item),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                  GroupsOverviewTab(
                    topInset: contentTopPadding,
                    onChanged: () => _load(silentRefresh: true),
                  ),
                ],
              ),
            ],
          ),
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
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1152D4).withValues(alpha: 0.35),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final statusColor = item.peerRole == 'lecturer'
        ? AppColors.roleLecturer
        : item.peerRole == 'admin' || item.peerRole == 'super_admin'
            ? AppColors.roleAdmin
            : AppColors.primary;
    final secondaryTextColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final primaryTextColor =
        isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage: item.peerPhotoUrl != null
                      ? CachedNetworkImageProvider(item.peerPhotoUrl!)
                      : null,
                  child: item.peerPhotoUrl == null
                      ? Text(
                          item.peerName.isNotEmpty
                              ? item.peerName[0].toUpperCase()
                              : '?',
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
                        style: GoogleFonts.plusJakartaSans(
                            fontSize: 15, fontWeight: FontWeight.w700),
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
                      const SizedBox(height: 6),
                      Text(
                        _formatRelative(item.acceptedAt),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  children: [
                    _ActionRailButton(
                      icon: Icons.visibility_rounded,
                      tooltip: 'View profile',
                      onPressed: item.peerId.isEmpty
                          ? null
                          : () => context.push(
                                '/user/${item.peerId}/portfolio',
                              ),
                    ),
                    const SizedBox(height: 8),
                    _ActionRailButton(
                      icon: Icons.chat_bubble_outline_rounded,
                      tooltip: 'Message peer',
                      onPressed: item.peerId.isEmpty
                          ? null
                          : () => context.push(
                                RouteNames.chatDetail
                                    .replaceFirst(':threadId', item.peerId),
                                extra: {
                                  'peerName': item.peerName,
                                  'peerPhotoUrl': item.peerPhotoUrl,
                                  'isPeerLecturer':
                                      item.peerRole == 'lecturer',
                                },
                              ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: AppColors.border(context),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Project',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  item.postTitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: primaryTextColor,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          if ((item.postCategory ?? '').trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MiniBadge(
                    label: item.postCategory!,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          if (item.message.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Details',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    item.message,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      color: secondaryTextColor,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _ActionRailButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  const _ActionRailButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
      ),
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        color: AppColors.primary,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
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

// ── Glow Blob ────────────────────────────────────────────────────────────────────────────
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
