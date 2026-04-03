import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';
import '../../shared/screens/offline_video_player_screen.dart';

class PostModerationReviewScreen extends StatefulWidget {
  const PostModerationReviewScreen({
    super.key,
    required this.postId,
  });

  final String postId;

  @override
  State<PostModerationReviewScreen> createState() =>
      _PostModerationReviewScreenState();
}

class _PostModerationReviewScreenState extends State<PostModerationReviewScreen> {
  final _postDao = sl<PostDao>();
  final _syncQueueDao = sl<SyncQueueDao>();
  final _syncService = sl<SyncService>();

  PostModel? _post;
  bool _loading = true;
  bool _processing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final post = await _postDao.getPostById(widget.postId);
    if (!mounted) return;
    setState(() {
      _post = post;
      _loading = false;
    });
  }

  Future<void> _setModerationStatus(ModerationStatus status) async {
    final post = _post;
    if (post == null) return;

    setState(() => _processing = true);
    await _postDao.updateModerationStatus(postId: post.id, status: status);

    final updated = await _postDao.getPostById(post.id);
    if (updated != null) {
      await _syncQueueDao.enqueue(
        operation: 'update',
        entity: 'posts',
        entityId: updated.id,
        payload: updated
            .copyWith(
              moderationStatus: status,
              updatedAt: DateTime.now(),
            )
            .toMap(),
      );
      await _syncService.processPendingSync();
    }

    if (!mounted) return;
    setState(() => _processing = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          status == ModerationStatus.approved
              ? 'Post approved and published.'
              : 'Post rejected.',
        ),
      ),
    );
    Navigator.of(context).pop(true);
  }

  Widget _metaChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
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

  Future<void> _openExternalUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  bool _isVideoUrl(String url) {
    if (isVideoMediaPath(url)) return true;
    final lower = url.toLowerCase();
    return RegExp(r'\.(mp4|mov|m4v|3gp|webm|mkv)(\?|$)').hasMatch(lower);
  }

  Widget _buildMediaPreview(String url, PostModel post) {
    if (_isVideoUrl(url)) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => OfflineVideoPlayerScreen(
                source: url,
                title: post.title,
              ),
            ),
          );
        },
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(color: AppColors.primaryTint10),
                const Center(
                  child: Icon(
                    Icons.play_circle_outline_rounded,
                    size: 58,
                    color: AppColors.primary,
                  ),
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'Video',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
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

    final image = isLocalMediaPath(url)
        ? Image.file(
            File(url),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: AppColors.primaryTint10,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
          )
        : CachedNetworkImage(
            imageUrl: url,
            fit: BoxFit.cover,
            placeholder: (_, __) => Container(color: AppColors.primaryTint10),
            errorWidget: (_, __, ___) => Container(
              color: AppColors.primaryTint10,
              alignment: Alignment.center,
              child: const Icon(
                Icons.image_not_supported_outlined,
                size: 36,
                color: AppColors.primary,
              ),
            ),
          );

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: image,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final post = _post;
    if (post == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Moderation Review')),
        body: const Center(child: Text('Post not found.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Moderation Review'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          Text(
            post.title,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metaChip('By ${post.authorName ?? post.authorId}', AppColors.primary),
              _metaChip(post.type.toUpperCase(), AppColors.warning),
              _metaChip(post.moderationStatus.name.toUpperCase(), AppColors.textSecondaryLight),
            ],
          ),
          const SizedBox(height: 14),
          if ((post.description ?? '').trim().isNotEmpty)
            Text(
              post.description!.trim(),
              style: GoogleFonts.plusJakartaSans(fontSize: 14, height: 1.45),
            ),
          if (post.skillsUsed.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Skills',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: post.skillsUsed
                  .map((skill) => _metaChip(skill, AppColors.success))
                  .toList(growable: false),
            ),
          ],
          if (post.externalLinks.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'External Links',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...post.externalLinks.map(
              (link) {
                final label = (link['label'] ?? '').trim();
                final url = (link['url'] ?? '').trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: url.isEmpty ? null : () => _openExternalUrl(url),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.borderLight),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.link_rounded,
                                size: 18,
                                color: AppColors.textSecondaryLight,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  label.isNotEmpty ? label : 'External Link',
                                  style: GoogleFonts.plusJakartaSans(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (url.isNotEmpty)
                                const Icon(
                                  Icons.open_in_new_rounded,
                                  size: 16,
                                  color: AppColors.textSecondaryLight,
                                ),
                            ],
                          ),
                          if (url.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            SelectableText(
                              url,
                              style: GoogleFonts.plusJakartaSans(
                                color: AppColors.primary,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
          if (post.youtubeUrl != null && post.youtubeUrl!.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'YouTube',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _openExternalUrl(post.youtubeUrl!.trim()),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.borderLight),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.ondemand_video_rounded, color: Colors.red),
                    const SizedBox(width: 10),
                    Expanded(
                      child: SelectableText(
                        post.youtubeUrl!.trim(),
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (post.mediaUrls.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Media',
              style: GoogleFonts.plusJakartaSans(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            ...post.mediaUrls.map(
              (url) {
                final cleanUrl = url.trim();
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMediaPreview(cleanUrl, post),
                      const SizedBox(height: 6),
                      SelectableText(
                        cleanUrl,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _setModerationStatus(ModerationStatus.approved),
                  icon: const Icon(Icons.check_circle_rounded),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: _processing
                      ? null
                      : () => _setModerationStatus(ModerationStatus.rejected),
                  icon: const Icon(Icons.cancel_rounded),
                  label: const Text('Reject'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
