// lib/features/feed/screens/author_portfolio_screen.dart
//
// MUST StarTrack — Author Portfolio Screen
//
// Read-only view of another user's profile and all their projects.
// Accessed from the feed's "View Details" action on any post.
//
// Layout:
//   • Profile header: avatar, display name, role badge, faculty/program,
//     bio, skills chips, stats row (posts, followers, following, collabs),
//     Follow & Message buttons.
//   • Projects list: each project as a tappable card showing thumbnail,
//     title, description, skills, and engagement stats.
//   • Tapping a project card opens the existing ProjectDetailScreen.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/router/route_names.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../features/auth/bloc/auth_cubit.dart';

class AuthorPortfolioScreen extends StatefulWidget {
  final String authorId;
  const AuthorPortfolioScreen({super.key, required this.authorId});

  @override
  State<AuthorPortfolioScreen> createState() => _AuthorPortfolioScreenState();
}

class _AuthorPortfolioScreenState extends State<AuthorPortfolioScreen> {
  UserModel? _user;
  List<PostModel> _posts = const [];
  bool _loading = true;
  String? _error;

  bool _isFollowing = false;
  bool _followLoading = false;

  final _userDao = UserDao();
  final _postDao = PostDao();
  final _syncQueue = SyncQueueDao();
  final _uuid = const Uuid();

  String? get _currentUserId =>
      sl<AuthCubit>().currentUser?.id ??
      FirebaseAuth.instance.currentUser?.uid;

  String get _currentUserName =>
      sl<AuthCubit>().currentUser?.displayName ??
      sl<AuthCubit>().currentUser?.email ??
      'Someone';

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // 1. Load user from local DB, fallback to Firestore
      UserModel? user = await _userDao.getUserById(widget.authorId);
      user ??= await sl<FirestoreService>().getUser(widget.authorId);

      // 2. Load their posts
      final posts = await _postDao.getPostsByAuthor(
        widget.authorId,
        pageSize: 100,
      );

      // 3. Check follow status
      bool isFollowing = false;
      final uid = _currentUserId;
      if (uid != null && user != null) {
        final db = await DatabaseHelper.instance.database;
        final rows = await db.query(
          DatabaseSchema.tableFollows,
          columns: ['id'],
          where: 'follower_id = ? AND followee_id = ?',
          whereArgs: [uid, widget.authorId],
          limit: 1,
        );
        isFollowing = rows.isNotEmpty;
      }

      if (mounted) {
        setState(() {
          _user = user;
          _posts = posts;
          _isFollowing = isFollowing;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load profile. Please try again.';
          _loading = false;
        });
      }
    }
  }

  // ── Follow / Unfollow ──────────────────────────────────────────────────────

  Future<void> _toggleFollow() async {
    final uid = _currentUserId;
    if (uid == null || _followLoading || uid == widget.authorId) return;

    setState(() => _followLoading = true);
    try {
      final db = await DatabaseHelper.instance.database;
      final existing = await db.query(
        DatabaseSchema.tableFollows,
        columns: ['id'],
        where: 'follower_id = ? AND followee_id = ?',
        whereArgs: [uid, widget.authorId],
        limit: 1,
      );

      if (existing.isEmpty) {
        await db.insert(DatabaseSchema.tableFollows, {
          'id': _uuid.v4(),
          'follower_id': uid,
          'followee_id': widget.authorId,
          'created_at': DateTime.now().millisecondsSinceEpoch.toString(),
          'sync_status': 0,
        });
        await _syncQueue.enqueue(
          operation: 'create',
          entity: 'follows',
          entityId: '${uid}_${widget.authorId}',
          payload: {
            'follower_id': uid,
            'following_id': widget.authorId,
            'follower_name': _currentUserName,
          },
        );
        await sl<ActivityLogDao>().logAction(
          userId: uid,
          action: 'follow_user',
          entityType: DatabaseSchema.tableUsers,
          entityId: widget.authorId,
        );
        if (mounted) setState(() => _isFollowing = true);
      } else {
        await db.delete(
          DatabaseSchema.tableFollows,
          where: 'follower_id = ? AND followee_id = ?',
          whereArgs: [uid, widget.authorId],
        );
        await _syncQueue.enqueue(
          operation: 'delete',
          entity: 'follows',
          entityId: '${uid}_${widget.authorId}',
          payload: {'follower_id': uid, 'following_id': widget.authorId},
        );
        if (mounted) setState(() => _isFollowing = false);
      }
    } finally {
      if (mounted) setState(() => _followLoading = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.backgroundDark : AppColors.backgroundLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          onPressed: () => context.pop(),
        ),
        title: _user != null
            ? Text(
                _user!.displayName ?? 'Portfolio',
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                  color: AppColors.textPrimary(context),
                ),
              )
            : const SizedBox.shrink(),
      ),
      body: _loading
          ? _buildSkeleton()
          : _error != null
              ? _buildError()
              : RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.primary,
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildProfileHeader(context, isDark)),
                      const SliverToBoxAdapter(child: SizedBox(height: 8)),
                      _buildProjectsHeader(context),
                      _posts.isEmpty
                          ? SliverToBoxAdapter(child: _buildEmptyProjects(context))
                          : SliverList(
                              delegate: SliverChildBuilderDelegate(
                                (ctx, i) => _ProjectCard(
                                  post: _posts[i],
                                  onTap: () => context.push(
                                    RouteNames.projectDetail.replaceFirst(
                                        ':postId', _posts[i].id),
                                  ),
                                ),
                                childCount: _posts.length,
                              ),
                            ),
                      const SliverToBoxAdapter(child: SizedBox(height: 32)),
                    ],
                  ),
                ),
    );
  }

  // ── Profile Header ─────────────────────────────────────────────────────────

  Widget _buildProfileHeader(BuildContext context, bool isDark) {
    final user = _user!;
    final profile = user.profile;
    final isOwnProfile = _currentUserId == user.id;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Avatar + name row ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Avatar(photoUrl: user.photoUrl, radius: 36),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.displayName ?? 'Unknown User',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      _RoleBadge(role: user.role),
                      if (profile?.programName != null ||
                          profile?.faculty != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          [
                            if (profile?.programName != null)
                              profile!.programName!,
                            if (profile?.faculty != null) profile!.faculty!,
                          ].join(' • '),
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (profile?.yearOfStudy != null &&
                          user.role == UserRole.student) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Year ${profile!.yearOfStudy}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondary(context),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Bio ────────────────────────────────────────────────────────────
          if (profile?.bio != null && profile!.bio!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                profile.bio!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 13.5,
                  color: AppColors.textPrimary(context),
                  height: 1.5,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),

          // ── Stats row ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatChip(
                  label: 'Posts',
                  value: profile?.totalPosts ?? _posts.length,
                ),
                _vDivider(),
                _StatChip(
                  label: 'Followers',
                  value: profile?.totalFollowers ?? 0,
                ),
                _vDivider(),
                _StatChip(
                  label: 'Following',
                  value: profile?.totalFollowing ?? 0,
                ),
                _vDivider(),
                _StatChip(
                  label: 'Collabs',
                  value: profile?.totalCollabs ?? 0,
                ),
              ],
            ),
          ),

          // ── Skills ─────────────────────────────────────────────────────────
          if (profile != null && profile.skills.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                'Skills',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textSecondary(context),
                  letterSpacing: 0.4,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: profile.skills
                    .take(12)
                    .map((s) => _SkillChip(label: s))
                    .toList(),
              ),
            ),
          ],

          // ── Action buttons ─────────────────────────────────────────────────
          if (!isOwnProfile)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: _FollowButton(
                      isFollowing: _isFollowing,
                      loading: _followLoading,
                      onTap: _toggleFollow,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(
                        RouteNames.chatDetail.replaceFirst(
                            ':threadId', widget.authorId),
                        extra: {
                          'peerName': user.displayName ?? '',
                          'peerPhotoUrl': user.photoUrl,
                          'isPeerLecturer':
                              user.role == UserRole.lecturer,
                        },
                      ),
                      icon: const Icon(Icons.chat_bubble_outline_rounded,
                          size: 16),
                      label: Text(
                        'Message',
                        style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w600),
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ── Projects section header ────────────────────────────────────────────────

  SliverToBoxAdapter _buildProjectsHeader(BuildContext context) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        child: Row(
          children: [
            Text(
              'Projects',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary(context),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primaryTint10,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_posts.length}',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ────────────────────────────────────────────────────────────

  Widget _buildEmptyProjects(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            const Icon(Icons.folder_open_rounded,
                size: 56, color: AppColors.borderLight),
            const SizedBox(height: 12),
            Text(
              'No projects yet',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary(context),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'This user hasn\'t posted any projects.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondary(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skeleton loader ────────────────────────────────────────────────────────

  Widget _buildSkeleton() {
    return const Center(
      child: CircularProgressIndicator(color: AppColors.primary),
    );
  }

  // ── Error state ────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: AppColors.danger),
            const SizedBox(height: 12),
            Text(
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: GoogleFonts.plusJakartaSans(
                color: AppColors.textPrimary(context),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _loading = true;
                  _error = null;
                });
                _load();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              child: Text('Retry',
                  style: GoogleFonts.plusJakartaSans(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _vDivider() => Container(
        width: 1,
        height: 28,
        color: AppColors.borderLight,
      );
}

// ── Project Card ──────────────────────────────────────────────────────────────

class _ProjectCard extends StatelessWidget {
  final PostModel post;
  final VoidCallback onTap;
  const _ProjectCard({required this.post, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDark : AppColors.surfaceLight;
    final border = isDark ? AppColors.borderDark : AppColors.borderLight;

    final thumbUrl = post.mediaUrls.isNotEmpty ? post.mediaUrls.first : null;
    final isOpportunity = post.type == 'opportunity';

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ────────────────────────────────────────────────────
            if (thumbUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(13)),
                child: _buildThumbnail(thumbUrl),
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Type badge + time ───────────────────────────────────
                  Row(
                    children: [
                      _TypeBadge(
                          isOpportunity: isOpportunity,
                          category: post.category),
                      const Spacer(),
                      Icon(Icons.access_time_rounded,
                          size: 12,
                          color: AppColors.textSecondary(context)),
                      const SizedBox(width: 3),
                      Text(
                        timeago.format(post.createdAt, locale: 'en_short'),
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: AppColors.textSecondary(context),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // ── Title ──────────────────────────────────────────────
                  Text(
                    post.title,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary(context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),

                  // ── Description ────────────────────────────────────────
                  if (post.description != null &&
                      post.description!.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      post.description!,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        color: AppColors.textSecondary(context),
                        height: 1.45,
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],

                  // ── Skills used ────────────────────────────────────────
                  if (post.skillsUsed.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 5,
                      runSpacing: 4,
                      children: post.skillsUsed
                          .take(6)
                          .map((s) => _SkillChip(label: s, small: true))
                          .toList(),
                    ),
                  ],

                  // ── Stats row ──────────────────────────────────────────
                  const SizedBox(height: 10),
                  _StatsRow(post: post),
                ],
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(String url) {
    // local paths start with / or contain a drive letter on Windows
    final isLocal = url.startsWith('/') ||
        url.startsWith('file://') ||
        RegExp(r'^[A-Za-z]:[\\\/]').hasMatch(url);

    if (isLocal) {
      return SizedBox(
        height: 180,
        width: double.infinity,
        child: Image.file(
          File(url),
          height: 180,
          width: double.infinity,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _thumbPlaceholder(),
        ),
      );
    }

    return CachedNetworkImage(
      imageUrl: url,
      height: 180,
      width: double.infinity,
      fit: BoxFit.cover,
      placeholder: (_, __) => _thumbPlaceholder(),
      errorWidget: (_, __, ___) => _thumbPlaceholder(),
    );
  }

  Widget _thumbPlaceholder() => Container(
        height: 180,
        width: double.infinity,
        color: AppColors.primaryTint10,
        child: const Icon(Icons.image_rounded,
            size: 40, color: AppColors.primary),
      );
}

// ── Stats Row ─────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  final PostModel post;
  const _StatsRow({required this.post});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _StatItem(
            icon: Icons.favorite_rounded,
            value: post.likeCount,
            color: AppColors.danger),
        const SizedBox(width: 14),
        _StatItem(
            icon: Icons.chat_bubble_rounded,
            value: post.commentCount,
            color: AppColors.primary),
        const SizedBox(width: 14),
        _StatItem(
            icon: Icons.visibility_rounded,
            value: post.viewCount,
            color: AppColors.textSecondary(context)),
        const SizedBox(width: 14),
        _StatItem(
            icon: Icons.share_rounded,
            value: post.shareCount,
            color: AppColors.textSecondary(context)),
        if (post.type == 'opportunity') ...[
          const SizedBox(width: 14),
          _StatItem(
              icon: Icons.group_add_rounded,
              value: post.joinCount,
              color: AppColors.mustGreen),
        ],
      ],
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final int value;
  final Color color;
  const _StatItem(
      {required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          _fmt(value),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

// ── Smaller shared widgets ────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final String? photoUrl;
  final double radius;
  const _Avatar({this.photoUrl, required this.radius});

  @override
  Widget build(BuildContext context) {
    if (photoUrl != null && photoUrl!.isNotEmpty) {
      final imageProvider = isLocalMediaPath(photoUrl!)
          ? FileImage(File(photoUrl!)) as ImageProvider<Object>
          : CachedNetworkImageProvider(photoUrl!);
      return CircleAvatar(
        radius: radius,
        backgroundColor: AppColors.primaryTint10,
        backgroundImage: imageProvider,
      );
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.primaryTint10,
      child: Icon(Icons.person_rounded,
          size: radius * 1.1, color: AppColors.primary),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final UserRole role;
  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = switch (role) {
      UserRole.lecturer => ('Lecturer', AppColors.roleLecturer, AppColors.roleLecturerBg),
      UserRole.admin => ('Admin', AppColors.roleAdmin, AppColors.roleAdminBg),
      UserRole.superAdmin => ('Super Admin', AppColors.roleSuperAdmin, AppColors.roleSuperAdminBg),
      _ => ('Student', AppColors.roleStudent, AppColors.roleStudentBg),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final int value;
  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          _fmt(value),
          style: GoogleFonts.plusJakartaSans(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary(context),
          ),
        ),
        Text(
          label,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.textSecondary(context),
          ),
        ),
      ],
    );
  }

  String _fmt(int n) {
    if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(1)}M';
    if (n >= 1000) return '${(n / 1000).toStringAsFixed(1)}K';
    return '$n';
  }
}

class _SkillChip extends StatelessWidget {
  final String label;
  final bool small;
  const _SkillChip({required this.label, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 9, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primaryTint20),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: small ? 11 : 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final bool isOpportunity;
  final String? category;
  const _TypeBadge({required this.isOpportunity, this.category});

  @override
  Widget build(BuildContext context) {
    final label = isOpportunity
        ? 'Opportunity'
        : (category?.isNotEmpty == true ? category! : 'Project');
    final color = isOpportunity ? AppColors.mustGreen : AppColors.primary;
    final bg = isOpportunity ? AppColors.mustGreenLight : AppColors.primaryTint10;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  final bool isFollowing;
  final bool loading;
  final VoidCallback onTap;
  const _FollowButton(
      {required this.isFollowing,
      required this.loading,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: loading ? null : onTap,
      icon: loading
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Colors.white))
          : Icon(
              isFollowing
                  ? Icons.person_remove_rounded
                  : Icons.person_add_rounded,
              size: 16,
            ),
      label: Text(
        isFollowing ? 'Unfollow' : 'Follow',
        style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: isFollowing ? AppColors.borderLight : AppColors.primary,
        foregroundColor: isFollowing ? AppColors.textPrimaryLight : Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
    );
  }
}
