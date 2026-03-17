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

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/models/post_model.dart';
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
  final _dao = PostDao();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final post = await _dao.getPostById(widget.postId);
      if (post != null) {
        await _dao.incrementViewCount(widget.postId);
      }
      setState(() {
        _post = post;
        _loading = false;
        _error = post == null ? 'Project not found.' : null;
      });
    } catch (e) {
      setState(() { _loading = false; _error = e.toString(); });
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

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // ── AppBar ──────────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 240,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            title: const Text('Project Showcase'),
            actions: [
              IconButton(
                icon: const Icon(Icons.share_rounded),
                onPressed: () {}, // Phase 4: share sheet
                tooltip: 'Share',
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
              _AuthorSnippet(post: post),
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
              _CollabSection(post: post),
              if (post.externalLinks.isNotEmpty)
                _ExternalLinks(links: post.externalLinks),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),

      // ── Sticky bottom bar ────────────────────────────────────────────────
      bottomNavigationBar: _StickyBar(post: post, onLike: () async {
        final dao = PostDao();
        await dao.toggleLike(postId: post.id, userId: '');
        setState(() {
          _post = post.copyWith(
            isLikedByMe: !post.isLikedByMe,
            likeCount: post.isLikedByMe
                ? post.likeCount - 1
                : post.likeCount + 1,
          );
        });
      }),
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
        // Photo count badge
        Positioned(
          bottom: 16,
          right: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.photo_library_outlined,
                    size: 14, color: Colors.white),
                const SizedBox(width: 4),
                Text('${currentIndex + 1}/${urls.length}',
                  style: GoogleFonts.lexend(
                    fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
              ],
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
  const _AuthorSnippet({required this.post});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        children: [
          CircleAvatar(
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
          const SizedBox(width: 12),
          Expanded(
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
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(
              minimumSize: const Size(0, 36),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              textStyle: GoogleFonts.lexend(
                fontSize: 13, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm)),
            ),
            child: const Text('Follow'),
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
  const _CollabSection({required this.post});

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
              onPressed: () {},
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

  const _StickyBar({required this.post, required this.onLike});

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
                onPressed: () {},
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {},
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