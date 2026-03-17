// lib/features/feed/screens/project_detail_screen.dart
//
// MUST StarTrack — Project Detail Screen (Phase 3)
//
// Matches project_detail_view.html exactly:
//   • Hero image with photo-count overlay
//   • Author snippet with Follow button
//   • Project overview + metric stats grid
//   • Skills used chips
//   • Collaboration section (hiring badge + member bubbles)
//   • External resource links (GitHub, PDF)
//   • Sticky bottom bar: like + collaborate
//
// HCI: clear visual hierarchy (F-pattern), sticky action bar,
//      error handling if post not found.

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'dart:ui';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/media_path_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/models/post_model.dart';
import '../../../features/auth/bloc/auth_cubit.dart';
import '../../shared/hci_components/post_card.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String postId;
  const ProjectDetailScreen({super.key, required this.postId});

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen> {
  PostModel? _post;
  bool _loading = true;
  String? _error;
  int _currentImageIndex = 0;
  bool _appBarOpaque = false;
  bool _isFollowing = false;
  bool _followLoading = false;
  final _dao = PostDao();
  final _syncQueue = SyncQueueDao();
  final _uuid = const Uuid();
  late final ScrollController _scrollCtrl;

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;

  // Hero height minus toolbar height = collapse threshold
  static const double _collapseAt = 240 - kToolbarHeight;

  @override
  void initState() {
    super.initState();
    _load();
    _scrollCtrl = ScrollController()
      ..addListener(() {
        final opaque = _scrollCtrl.offset > _collapseAt;
        if (opaque != _appBarOpaque) {
          setState(() => _appBarOpaque = opaque);
        }
      });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final post = await _dao.getPostById(widget.postId);
      bool isFollowing = false;
      if (post != null) {
        await _dao.incrementViewCount(widget.postId);
        final uid = _currentUserId;
        if (uid != null) {
          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            DatabaseSchema.tableFollows,
            where: 'follower_id = ? AND followee_id = ?',
            whereArgs: [uid, post.authorId],
            limit: 1,
          );
          isFollowing = rows.isNotEmpty;
        }
      }
      setState(() {
        _post = post;
        _loading = false;
        _isFollowing = isFollowing;
        _error = post == null ? 'Project not found.' : null;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
    }
  }

  Future<void> _toggleFollow() async {
    final uid = _currentUserId;
    final post = _post;
    if (uid == null || post == null || _followLoading) return;
    setState(() => _followLoading = true);
    final wasFollowing = _isFollowing;
    setState(() => _isFollowing = !wasFollowing);
    try {
      final db = await DatabaseHelper.instance.database;
      if (!wasFollowing) {
        await db.insert(DatabaseSchema.tableFollows, {
          'id': _uuid.v4(),
          'follower_id': uid,
          'followee_id': post.authorId,
          'created_at': DateTime.now().millisecondsSinceEpoch.toString(),
          'sync_status': 0,
        });
        await _syncQueue.enqueue(
          operation: 'create',
          entity: 'follows',
          entityId: '${uid}_${post.authorId}',
          payload: {'follower_id': uid, 'following_id': post.authorId},
        );
      } else {
        await db.delete(
          DatabaseSchema.tableFollows,
          where: 'follower_id = ? AND followee_id = ?',
          whereArgs: [uid, post.authorId],
        );
        await _syncQueue.enqueue(
          operation: 'delete',
          entity: 'follows',
          entityId: '${uid}_${post.authorId}',
          payload: {'follower_id': uid, 'following_id': post.authorId},
        );
      }
    } catch (_) {
      setState(() => _isFollowing = wasFollowing);
    } finally {
      setState(() => _followLoading = false);
    }
  }

  void _sharePost() {
    final post = _post;
    if (post == null) return;
    Share.share('${post.title}\n\nCheck out this project on MUST StarTrack!');
  }

  Future<void> _requestCollaborate() async {
    final post = _post;
    final uid = _currentUserId;
    if (post == null || !mounted) return;
    final messageCtrl = TextEditingController();
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SingleChildScrollView(
        padding: EdgeInsets.only(
          left: 20, right: 20, top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request to Collaborate',
              style: GoogleFonts.lexend(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Send a message to ${post.authorName ?? "the author"}',
              style: GoogleFonts.lexend(
                fontSize: 13, color: AppColors.textSecondaryLight)),
            const SizedBox(height: 16),
            TextField(
              controller: messageCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe your skills and how you can contribute…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(minimumSize: const Size(0, 48)),
                child: const Text('Send Request'),
              ),
            ),
          ],
        ),
      ),
    );
    final message = messageCtrl.text.trim();
    // Do NOT call messageCtrl.dispose() here — the bottom sheet widget tree
    // is still unwinding (TextField animation listener) when the future
    // resolves. The local variable will be GC'd naturally after this scope.
    if (confirmed != true || uid == null) return;
    try {
      final db = await DatabaseHelper.instance.database;
      await db.insert(DatabaseSchema.tableCollabRequests, {
        'id': _uuid.v4(),
        'sender_id': uid,
        'receiver_id': post.authorId,
        'post_id': post.id,
        'message': message,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Collaboration request sent!'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send request: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null || _post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Project')),
        body: Center(child: Text(_error ?? 'Not found.')),
      );
    }

    final post = _post!;

    final Color barBg = _appBarOpaque
        ? Theme.of(context).scaffoldBackgroundColor
        : Colors.transparent;
    final Color iconColor =
        _appBarOpaque ? AppColors.primary : Colors.white;

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollCtrl,
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            backgroundColor: barBg,
            surfaceTintColor: Colors.transparent,
            elevation: _appBarOpaque ? 0 : 0,
            scrolledUnderElevation: 1,
            shadowColor: Colors.black12,
            forceMaterialTransparency: !_appBarOpaque,
            leading: Padding(
              padding: const EdgeInsets.all(8),
              child: _appBarOpaque
                  ? _SolidIconButton(
                      icon: Icons.arrow_back_rounded,
                      color: iconColor,
                      onPressed: () => context.pop(),
                    )
                  : _GlassIconButton(
                      icon: Icons.arrow_back_rounded,
                      onPressed: () => context.pop(),
                    ),
            ),
            title: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _appBarOpaque
                  ? Text(
                      'Project Showcase',
                      key: const ValueKey('opaque'),
                      style: GoogleFonts.lexend(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryLight,
                      ),
                    )
                  : _GlassPill(
                      key: const ValueKey('glass'),
                      child: Text(
                        'Project Showcase',
                        style: GoogleFonts.lexend(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            centerTitle: true,
            actions: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 8, 8),
                child: _appBarOpaque
                    ? _SolidIconButton(
                        icon: Icons.share_rounded,
                        color: iconColor,
                        onPressed: _sharePost,
                      )
                    : _GlassIconButton(
                        icon: Icons.share_rounded,
                        onPressed: _sharePost,
                      ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: _HeroGallery(
                urls: post.mediaUrls,
                currentIndex: _currentImageIndex,
                onPageChanged: (i) => setState(() => _currentImageIndex = i),
              ),
            ),
          ),

          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
                child: Row(
                  children: [
                    const Icon(Icons.folder_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(post.category ?? post.type,
                      style: GoogleFonts.lexend(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(post.title,
                  style: GoogleFonts.lexend(
                    fontSize: 26, fontWeight: FontWeight.w700,
                    letterSpacing: -0.4, height: 1.2)),
              ),
              _AuthorSnippet(
                post: post,
                isFollowing: _isFollowing,
                followLoading: _followLoading,
                onFollow: _toggleFollow,
                onAuthorTap: () => context.go('/profile/${post.authorId}'),
              ),
              const Divider(height: 1),
              if (post.description != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Project Overview',
                    style: GoogleFonts.lexend(
                      fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(post.description!,
                    style: GoogleFonts.lexend(
                      fontSize: 14, color: AppColors.textSecondaryLight,
                      height: 1.6)),
                ),
              ],
              _StatsGrid(post: post),
              if (post.skillsUsed.isNotEmpty) _SkillsSection(post: post),
              _CollabSection(post: post, onCollaborate: _requestCollaborate),
              if (post.externalLinks.isNotEmpty)
                _ExternalLinks(links: post.externalLinks),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),

      // ── Sticky bottom bar ────────────────────────────────────────────────
      bottomNavigationBar: _StickyBar(
        post: post,
        onShare: _sharePost,
        onCollaborate: _requestCollaborate,
        onLike: () async {
          final uid = _currentUserId ?? '';
          await _dao.toggleLike(postId: post.id, userId: uid);
          if (uid.isNotEmpty) {
            await _syncQueue.enqueue(
              operation: post.isLikedByMe ? 'delete' : 'create',
              entity: 'likes',
              entityId: '${uid}_${post.id}',
              payload: {'user_id': uid, 'post_id': post.id},
            );
          }
          setState(() {
            _post = post.copyWith(
              isLikedByMe: !post.isLikedByMe,
              likeCount: post.isLikedByMe
                  ? post.likeCount - 1
                  : post.likeCount + 1,
            );
          });
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero image gallery
// ─────────────────────────────────────────────────────────────────────────────

class _HeroGallery extends StatelessWidget {
  final List<String> urls;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;

  const _HeroGallery({
    required this.urls,
    required this.currentIndex,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) {
      return Container(
        color: AppColors.primaryTint10,
        child: const Center(
          child: Icon(Icons.rocket_launch_rounded, size: 80, color: AppColors.primary),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        PageView.builder(
          itemCount: urls.length,
          onPageChanged: onPageChanged,
          itemBuilder: (_, i) => _isVideoUrl(urls[i])
              ? Container(
                  color: AppColors.primaryTint10,
                  child: const Center(
                    child: Icon(Icons.play_circle_outline_rounded,
                        size: 72, color: AppColors.primary),
                  ),
                )
              : isLocalMediaPath(urls[i])
                  ? Image.file(
                      File(urls[i]),
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppColors.primaryTint10,
                        child: const Icon(Icons.image_outlined, size: 60, color: AppColors.primary),
                      ),
                    )
                  : CachedNetworkImage(
                      imageUrl: urls[i],
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.primaryTint10,
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.primaryTint10,
                        child: const Icon(Icons.image_outlined, size: 60, color: AppColors.primary),
                      ),
                    ),
        ),
        // Slideshow dot indicators
        if (urls.length > 1)
          Positioned(
            bottom: 16,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(
                urls.length,
                (i) => AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: i == currentIndex ? 20 : 7,
                  height: 7,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(
                    color: i == currentIndex
                        ? Colors.white
                        : Colors.white.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

bool _isVideoUrl(String url) {
  return isVideoMediaPath(url);
}

// ─────────────────────────────────────────────────────────────────────────────
// Author snippet
// ─────────────────────────────────────────────────────────────────────────────

class _AuthorSnippet extends StatelessWidget {
  final PostModel post;
  final bool isFollowing;
  final bool followLoading;
  final VoidCallback onFollow;
  final VoidCallback onAuthorTap;

  const _AuthorSnippet({
    required this.post,
    required this.isFollowing,
    required this.followLoading,
    required this.onFollow,
    required this.onAuthorTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          GestureDetector(
            onTap: onAuthorTap,
            child: CircleAvatar(
              radius: 24,
              backgroundColor: AppColors.primaryTint10,
              backgroundImage: post.authorPhotoUrl != null
                  ? NetworkImage(post.authorPhotoUrl!)
                  : null,
              child: post.authorPhotoUrl == null
                  ? Text(
                      post.authorName?.isNotEmpty == true
                          ? post.authorName![0].toUpperCase()
                          : '?',
                      style: GoogleFonts.lexend(
                        fontSize: 18, fontWeight: FontWeight.w700,
                        color: AppColors.primary))
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: onAuthorTap,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(post.authorName ?? 'Unknown',
                    style: GoogleFonts.lexend(
                      fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(post.faculty ?? post.authorRole ?? '',
                    style: GoogleFonts.lexend(
                      fontSize: 12, color: AppColors.textSecondaryLight)),
                ],
              ),
            ),
          ),
          if (followLoading)
            const SizedBox(
              width: 36, height: 36,
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            ElevatedButton(
              onPressed: onFollow,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: GoogleFonts.lexend(
                  fontSize: 13, fontWeight: FontWeight.w700),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
                backgroundColor:
                    isFollowing ? Colors.transparent : AppColors.primary,
                foregroundColor:
                    isFollowing ? AppColors.primary : Colors.white,
                side: isFollowing
                    ? const BorderSide(color: AppColors.primary)
                    : null,
              ),
              child: Text(isFollowing ? 'Following' : 'Follow'),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats grid
// ─────────────────────────────────────────────────────────────────────────────

class _StatsGrid extends StatelessWidget {
  final PostModel post;
  const _StatsGrid({required this.post});

  @override
  Widget build(BuildContext context) {
    final stats = [
      ('Views', '${post.viewCount}', Icons.visibility_outlined),
      ('Likes', '${post.likeCount}', Icons.favorite_border_rounded),
      ('Comments', '${post.commentCount}', Icons.chat_bubble_outline_rounded),
      ('Members', '4', Icons.group_outlined),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 2.4,
        children: stats.map((s) {
          final (label, value, icon) = s;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.12)),
            ),
            child: Row(
              children: [
                Icon(icon, size: 18, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(value,
                        style: GoogleFonts.lexend(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                        overflow: TextOverflow.ellipsis),
                      Text(label,
                        style: GoogleFonts.lexend(
                          fontSize: 10, color: AppColors.textSecondaryLight,
                          fontWeight: FontWeight.w600),
                        overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Skills section
// ─────────────────────────────────────────────────────────────────────────────

class _SkillsSection extends StatelessWidget {
  final PostModel post;
  const _SkillsSection({required this.post});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).cardColor,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Skills Used',
            style: GoogleFonts.lexend(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: post.skillsUsed.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(s, style: GoogleFonts.lexend(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: AppColors.textSecondaryLight)),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Collaboration section
// ─────────────────────────────────────────────────────────────────────────────

class _CollabSection extends StatelessWidget {
  final PostModel post;
  final VoidCallback onCollaborate;
  const _CollabSection({required this.post, required this.onCollaborate});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Collaboration',
                style: GoogleFonts.lexend(
                  fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('HIRING',
                  style: GoogleFonts.lexend(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: AppColors.success, letterSpacing: 0.08)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '"Looking for collaborators to help bring this project to life."',
            style: GoogleFonts.lexend(
              fontSize: 13, fontStyle: FontStyle.italic,
              color: AppColors.textSecondaryLight, height: 1.5),
          ),
          const SizedBox(height: 12),
          const CollaboratorBubbles(photoUrls: [null, null], totalCount: 4),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCollaborate,
              icon: const Icon(Icons.group_add_rounded),
              label: const Text('Request to Collaborate'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusMd)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// External links
// ─────────────────────────────────────────────────────────────────────────────

class _ExternalLinks extends StatelessWidget {
  final List<Map<String, String>> links;
  const _ExternalLinks({required this.links});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('External Resources',
            style: GoogleFonts.lexend(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          ...links.map((link) => _LinkRow(link: link)),
        ],
      ),
    );
  }
}

class _LinkRow extends StatelessWidget {
  final Map<String, String> link;
  const _LinkRow({required this.link});

  @override
  Widget build(BuildContext context) {
    final label = link['label'] ?? link['url'] ?? 'Link';
    final url = link['url'] ?? '';
    final isGithub = label.toLowerCase().contains('github');

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () async {
          final uri = Uri.tryParse(url);
          if (uri != null) await launchUrl(uri);
        },
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.borderLight),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
          ),
          child: Row(
            children: [
              Icon(
                isGithub ? Icons.code_rounded : Icons.description_outlined,
                size: 20, color: AppColors.textSecondaryLight),
              const SizedBox(width: 12),
              Expanded(child: Text(label,
                style: GoogleFonts.lexend(fontSize: 14, fontWeight: FontWeight.w500))),
              const Icon(Icons.open_in_new_rounded,
                  size: 16, color: AppColors.textSecondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sticky bottom bar
// ─────────────────────────────────────────────────────────────────────────────

class _StickyBar extends StatelessWidget {
  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onCollaborate;

  const _StickyBar({
    required this.post,
    required this.onLike,
    required this.onShare,
    required this.onCollaborate,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: SizedBox(
          width: double.infinity,
          child: Row(
            children: [
              IconButton(
                onPressed: onLike,
                icon: Icon(
                  post.isLikedByMe
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: post.isLikedByMe ? AppColors.danger : null,
                ),
                tooltip: 'Like',
              ),
              Text(
                '${post.likeCount}',
                style: GoogleFonts.lexend(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onCollaborate,
                  icon: const Icon(Icons.group_add_rounded, size: 18),
                  label: const Text('Collaborate'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Glass UI helpers — AppBar overlays
// ─────────────────────────────────────────────────────────────────────────────

// Plain icon button for the opaque/white AppBar state
class _SolidIconButton extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  const _SolidIconButton({
    required this.icon,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Center(child: Icon(icon, size: 20, color: color)),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;

  const _GlassIconButton({required this.icon, this.onPressed});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onPressed,
              borderRadius: BorderRadius.circular(12),
              child: Center(
                child: Icon(icon, size: 18, color: Colors.white),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassPill extends StatelessWidget {
  final Widget child;

  const _GlassPill({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.28),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}