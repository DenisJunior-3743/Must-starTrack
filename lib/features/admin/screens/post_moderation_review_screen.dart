import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/sync_service.dart';

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
              (link) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText(
                  link['url'] ?? '',
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
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
              (url) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SelectableText(
                  url,
                  style: GoogleFonts.plusJakartaSans(
                    color: AppColors.primary,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
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
