// lib/features/feed/screens/project_detail_screen.dart
//
// MUST StarTrack â€” Project Detail Screen (Phase 3)
//
// Matches project_detail_view.html exactly:
//   â€¢ Hero image with photo-count overlay
//   â€¢ Author snippet with Follow button
//   â€¢ Project overview + metric stats grid
//   â€¢ Skills used chips
//   â€¢ Collaboration section (hiring badge + member bubbles)
//   â€¢ External resource links (GitHub, PDF)
//   â€¢ Sticky bottom bar: like + collaborate
//
// HCI: clear visual hierarchy (F-pattern), sticky action bar,
//      error handling if post not found.

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
import 'dart:io';
import 'dart:ui';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/utils/media_path_utils.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/activity_log_dao.dart';
import '../../../data/local/dao/comment_dao.dart';
import '../../../data/local/dao/notification_dao.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/database_helper.dart';
import '../../../data/local/schema/database_schema.dart';
import '../../../data/models/post_model.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/remote/sync_service.dart';
import '../../../features/auth/bloc/auth_cubit.dart';
import '../../../features/notifications/bloc/notification_cubit.dart';
import '../../shared/screens/offline_video_player_screen.dart';
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
  bool _commentSubmitting = false;
  CommentRecord? _replyingTo;
  bool _hasJoined = false;
  bool _joinLoading = false;
  final _dao = PostDao();
  final _syncQueue = SyncQueueDao();
  final _uuid = const Uuid();
  final _commentCtrl = TextEditingController();
  late final ScrollController _scrollCtrl;
  List<CommentRecord> _comments = const [];

  String? get _currentUserId => sl<AuthCubit>().currentUser?.id;
  String get _currentUserName =>
      sl<AuthCubit>().currentUser?.displayName
      ?? sl<AuthCubit>().currentUser?.email
      ?? 'Someone';

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
    _commentCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      var post = await _dao.getPostById(widget.postId);

      // Fallback: if not cached locally, fetch from Firestore and cache it.
      if (post == null && FirebaseAuth.instance.currentUser != null) {
        debugPrint('[ProjectDetail] Post ${widget.postId} not in local DB â€” fetching from Firestore');
        final remote = await sl<FirestoreService>().getPostById(widget.postId);
        if (remote != null) {
          await _dao.insertPost(remote);
          post = remote;
          debugPrint('[ProjectDetail] Cached post ${widget.postId} from Firestore');
        }
      }

      bool isFollowing = false;
      var comments = const <CommentRecord>[];
      if (post != null) {
        final uid = _currentUserId;
        if (uid != null) {
          final isNewView = await _dao.recordUniqueView(
            postId: widget.postId,
            userId: uid,
          );
          debugPrint('[ProjectDetail] View check post=${widget.postId} user=$uid isNewView=$isNewView');
          if (isNewView) {
            await _dao.incrementViewCount(widget.postId);
            post = post.copyWith(viewCount: post.viewCount + 1);
            await _syncQueue.enqueue(
              operation: 'create',
              entity: 'post_views',
              entityId: '${uid}_${post.id}',
              payload: {
                'viewer_id': uid,
                'viewer_name': _currentUserName,
                'author_id': post.authorId,
                'post_id': post.id,
                'post_title': post.title,
              },
            );
            debugPrint('[ProjectDetail] Queued unique view sync post=${post.id} viewer=$uid author=${post.authorId}');
            unawaited(sl<SyncService>().processPendingSync());
          }

          final db = await DatabaseHelper.instance.database;
          final rows = await db.query(
            DatabaseSchema.tableFollows,
            where: 'follower_id = ? AND followee_id = ?',
            whereArgs: [uid, post.authorId],
            limit: 1,
          );
          isFollowing = rows.isNotEmpty;
        }

        if (post.type == 'opportunity' && uid != null) {
          _hasJoined = await _dao.hasJoinedPost(postId: post.id, userId: uid);
        }

        if (FirebaseAuth.instance.currentUser != null) {
          await sl<SyncService>().syncCommentsForPost(widget.postId);
        }
        comments = await sl<CommentDao>().getCommentsForPost(widget.postId);
      }
      setState(() {
        _post = post;
        _comments = comments;
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
    if (uid == null || post == null || _followLoading || uid == post.authorId) {
      return;
    }
    setState(() => _followLoading = true);
    try {
      debugPrint('[ProjectDetail] Attempting follow toggle follower=$uid followee=${post.authorId}');
      final db = await DatabaseHelper.instance.database;
      final existing = await db.query(
        DatabaseSchema.tableFollows,
        columns: ['id'],
        where: 'follower_id = ? AND followee_id = ?',
        whereArgs: [uid, post.authorId],
        limit: 1,
      );
      if (existing.isEmpty) {
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
          payload: {
            'follower_id': uid,
            'following_id': post.authorId,
            'follower_name': _currentUserName,
          },
        );
        debugPrint('[ProjectDetail] Follow queued follower=$uid followee=${post.authorId}');
        await sl<ActivityLogDao>().logAction(
          userId: uid,
          action: 'follow_user',
          entityType: DatabaseSchema.tableUsers,
          entityId: post.authorId,
          metadata: {'post_id': post.id},
        );
        setState(() => _isFollowing = true);
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
          payload: {
            'follower_id': uid,
            'following_id': post.authorId,
          },
        );
        debugPrint('[ProjectDetail] Unfollow queued follower=$uid followee=${post.authorId}');
        setState(() => _isFollowing = false);
      }
      unawaited(sl<SyncService>().processPendingSync());
    } catch (_) {
      debugPrint('[ProjectDetail] Follow toggle failed follower=$uid followee=${post.authorId}');
    } finally {
      setState(() => _followLoading = false);
    }
  }

  Future<void> _submitComment() async {
    final post = _post;
    final user = sl<AuthCubit>().currentUser;
    final content = _commentCtrl.text.trim();
    if (post == null || user == null || content.isEmpty || _commentSubmitting) {
      return;
    }

    setState(() => _commentSubmitting = true);
    try {
      final commentId = _uuid.v4();
      final parentId = _replyingTo?.id;
      await sl<CommentDao>().addLocalComment(
        postId: post.id,
        authorId: user.id,
        content: content,
        commentId: commentId,
        parentCommentId: parentId,
      );
      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'comments',
        entityId: commentId,
        payload: {
          'post_id': post.id,
          'author_id': user.id,
          'receiver_id': post.authorId,
          'commenter_name': _currentUserName,
          'post_title': post.title,
          'content': content,
          if (parentId != null) 'parent_comment_id': parentId,
        },
      );
      await sl<ActivityLogDao>().logAction(
        userId: user.id,
        action: parentId == null ? 'comment_post' : 'reply_comment',
        entityType: DatabaseSchema.tablePosts,
        entityId: post.id,
        metadata: {'comment_id': commentId},
      );

      _commentCtrl.clear();
      final newComment = CommentRecord(
        id: commentId,
        postId: post.id,
        authorId: user.id,
        content: content,
        createdAt: DateTime.now(),
        authorName: _currentUserName,
        parentCommentId: parentId,
      );
      setState(() {
        _comments = [newComment, ..._comments];
        _replyingTo = null;
        _post = post.copyWith(commentCount: post.commentCount + 1);
      });
      unawaited(sl<SyncService>().processPendingSync());
    } finally {
      if (mounted) {
        setState(() => _commentSubmitting = false);
      }
    }
  }

  void _sharePost() {
    final post = _post;
    if (post == null) return;
    final uid = _currentUserId;
    if (uid != null && uid.isNotEmpty) {
      unawaited(sl<ActivityLogDao>().logAction(
        userId: uid,
        action: 'share_post',
        entityType: DatabaseSchema.tablePosts,
        entityId: post.id,
        metadata: {'post_title': post.title},
      ));
    }
    Share.share('${post.title}\n\nCheck out this project on MUST StarTrack!');
  }

  Future<void> _reportPost(PostModel post) async {
    final uid = _currentUserId;
    if (uid == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Log in to report posts'),
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final reasons = [
      'Spam or misleading',
      'Inappropriate content',
      'Plagiarism',
      'Harassment or bullying',
      'Other',
    ];
    String? selectedReason;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 20, right: 20, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom +
                MediaQuery.of(ctx).padding.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Report Post',
                style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text('Why are you reporting this post?',
                style: GoogleFonts.plusJakartaSans(fontSize: 13, color: AppColors.textSecondaryLight)),
              const SizedBox(height: 16),
              RadioGroup<String>(
                groupValue: selectedReason ?? '',
                onChanged: (v) => setSheetState(() => selectedReason = v),
                child: Column(
                  children: reasons.map((r) => RadioListTile<String>(
                    title: Text(r, style: GoogleFonts.plusJakartaSans(fontSize: 14)),
                    value: r,
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                  )).toList(),
                ),
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedReason != null
                      ? () => Navigator.pop(ctx, true)
                      : null,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    backgroundColor: AppColors.danger,
                  ),
                  child: const Text('Submit Report'),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (confirmed != true || selectedReason == null) return;

    try {
      final db = await DatabaseHelper.instance.database;
      final reportId = _uuid.v4();
      await db.insert(DatabaseSchema.tableModerationQueue, {
        'id': reportId,
        'post_id': post.id,
        'reporter_id': uid,
        'reason': selectedReason,
        'suspicion_score': 0.0,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      });
      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'moderation_queue',
        entityId: reportId,
        payload: {
          'post_id': post.id,
          'reporter_id': uid,
          'reason': selectedReason,
          'post_title': post.title,
          'author_id': post.authorId,
        },
      );
      unawaited(sl<SyncService>().processPendingSync());

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Report submitted. Our team will review it.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to report: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
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
          bottom: MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Request to Collaborate',
              style: GoogleFonts.plusJakartaSans(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('Send a message to ${post.authorName ?? "the author"}',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13, color: AppColors.textSecondaryLight)),
            const SizedBox(height: 16),
            TextField(
              controller: messageCtrl,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: 'Describe your skills and how you can contributeâ€¦',
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
    // Do NOT call messageCtrl.dispose() here â€” the bottom sheet widget tree
    // is still unwinding (TextField animation listener) when the future
    // resolves. The local variable will be GC'd naturally after this scope.
    debugPrint('[Collab] Sheet closed â€” confirmed=$confirmed uid=$uid message="$message"');
    if (confirmed != true || uid == null) {
      debugPrint('[Collab] Aborted: confirmed=$confirmed, uid=$uid');
      return;
    }
    try {
      final collabId = _uuid.v4();
      debugPrint('[Collab] Inserting SQLite row â€” id=$collabId sender=$uid receiver=${_post?.authorId} postId=${_post?.id}');
      final db = await DatabaseHelper.instance.database;
      await db.insert(DatabaseSchema.tableCollabRequests, {
        'id': collabId,
        'sender_id': uid,
        'receiver_id': post.authorId,
        'post_id': post.id,
        'message': message,
        'status': 'pending',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
        'sync_status': 0,
      });

      debugPrint('[Collab] âœ… SQLite insert OK â€” collabId=$collabId');

      // Push the collab request to Firestore via the sync queue.
      debugPrint('[Collab] Enqueuing sync job for collabId=$collabId');
      final senderName = sl<AuthCubit>().currentUser?.displayName
          ?? sl<AuthCubit>().currentUser?.email
          ?? 'Someone';
      await _syncQueue.enqueue(
        operation: 'create',
        entity: 'collab_requests',
        entityId: collabId,
        payload: {
          'sender_id': uid,
          'sender_name': senderName,
          'receiver_id': post.authorId,
          'post_id': post.id,
          'post_title': post.title,
          'message': message,
          'status': 'pending',
        },
      );
      await sl<ActivityLogDao>().logAction(
        userId: uid,
        action: 'send_collab_request',
        entityType: DatabaseSchema.tableCollabRequests,
        entityId: collabId,
        metadata: {'post_id': post.id, 'receiver_id': post.authorId},
      );
      debugPrint('[Collab] âœ… Sync job enqueued for collabId=$collabId');
      // Trigger immediate sync so the collab request reaches Firestore now.
      unawaited(sl<SyncService>().processPendingSync());

      // Insert a local confirmation notification for the sender (current user).
      // The receiver's notification is written to Firestore by _syncCollabRequest
      // and pulled into their SQLite on next syncRemoteToLocal.
      await sl<NotificationDao>().insertNotification(NotificationModel(
        id: _uuid.v4(),
        userId: uid,
        type: 'collaboration',
        body: 'Collaboration request sent to ${post.authorName ?? "the author"} for "${post.title}"',
        detail: message.isNotEmpty ? message : null,
        entityId: collabId,
        createdAt: DateTime.now(),
      ));

      if (mounted) {
        unawaited(context.read<NotificationCubit>().loadNotifications());
      }

      debugPrint('[Collab] âœ… Notification inserted for author=${post.authorId}');
      debugPrint('[Collab] âœ… All steps complete for collabId=$collabId');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Collaboration request sent!'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e, st) {
      debugPrint('[Collab] âŒ Error: $e');
      debugPrint('[Collab] âŒ Stacktrace: $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed to send request: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  Future<void> _joinOpportunity() async {
    final post = _post;
    final uid = _currentUserId;
    if (post == null || uid == null || _joinLoading) return;

    setState(() => _joinLoading = true);
    try {
      final isNowJoined = await _dao.toggleJoin(postId: post.id, userId: uid);
      debugPrint('[Join] post=${post.id} user=$uid isNowJoined=$isNowJoined');
      await sl<ActivityLogDao>().logAction(
        userId: uid,
        action: isNowJoined ? 'join_opportunity' : 'leave_opportunity',
        entityType: DatabaseSchema.tablePosts,
        entityId: post.id,
        metadata: {'post_title': post.title},
      );

      final joinId = _uuid.v4();
      await _syncQueue.enqueue(
        operation: isNowJoined ? 'create' : 'delete',
        entity: 'opportunity_joins',
        entityId: '${uid}_${post.id}',
        payload: {
          'id': joinId,
          'user_id': uid,
          'post_id': post.id,
          'post_title': post.title,
          'author_id': post.authorId,
          'actor_name': _currentUserName,
          'is_joining': isNowJoined,
        },
      );
      unawaited(sl<SyncService>().processPendingSync());

      if (isNowJoined) {
        await sl<NotificationDao>().insertNotification(NotificationModel(
          id: _uuid.v4(),
          userId: uid,
          type: 'opportunity',
          body: 'You joined "${post.title}"',
          entityId: post.id,
          createdAt: DateTime.now(),
        ));
        if (mounted) {
          unawaited(context.read<NotificationCubit>().loadNotifications());
        }
      }

      setState(() {
        _hasJoined = isNowJoined;
        _post = post.copyWith(
          joinCount: isNowJoined ? post.joinCount + 1 : (post.joinCount - 1).clamp(0, 9999),
        );
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(isNowJoined
              ? 'You joined this opportunity!'
              : 'You left this opportunity.'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('[Join] âŒ $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Failed: $e'),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _joinLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
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
          // â”€â”€ AppBar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
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
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimaryLight,
                      ),
                    )
                  : _GlassPill(
                      key: const ValueKey('glass'),
                      child: Text(
                        'Project Showcase',
                        style: GoogleFonts.plusJakartaSans(
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
                padding: const EdgeInsets.fromLTRB(0, 8, 4, 8),
                child: _appBarOpaque
                    ? _SolidIconButton(
                        icon: Icons.flag_outlined,
                        color: iconColor,
                        onPressed: () => _reportPost(post),
                      )
                    : _GlassIconButton(
                        icon: Icons.flag_outlined,
                        onPressed: () => _reportPost(post),
                      ),
              ),
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
                title: post.title,
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
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13, fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text(post.title,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 26, fontWeight: FontWeight.w700,
                    letterSpacing: -0.4, height: 1.2)),
              ),
              _AuthorSnippet(
                post: post,
                isFollowing: _isFollowing,
                followLoading: _followLoading,
                canFollow: _currentUserId != post.authorId,
                onFollow: _toggleFollow,
                onAuthorTap: () => context.go('/profile/${post.authorId}'),
              ),
              const Divider(height: 1),
              if (post.description != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text('Project Overview',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 17, fontWeight: FontWeight.w700)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Text(post.description!,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, color: AppColors.textSecondaryLight,
                      height: 1.6)),
                ),
              ],
              _StatsGrid(post: post),
              if (post.type == 'opportunity')
                _OpportunityMeta(post: post),
              _CommentsSection(
                comments: _comments,
                controller: _commentCtrl,
                isSubmitting: _commentSubmitting,
                onSubmit: _submitComment,
                replyingTo: _replyingTo,
                onReply: (c) => setState(() {
                  _replyingTo = c;
                  _commentCtrl.clear();
                }),
                onCancelReply: () => setState(() => _replyingTo = null),
              ),
              if (post.skillsUsed.isNotEmpty) _SkillsSection(post: post),
              _CollabSection(post: post, onCollaborate: _requestCollaborate),
              if (post.externalLinks.isNotEmpty)
                _ExternalLinks(links: post.externalLinks),
              const SizedBox(height: 100),
            ]),
          ),
        ],
      ),

      // â”€â”€ Sticky bottom bar â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      bottomNavigationBar: _StickyBar(
        post: post,
        onShare: _sharePost,
        onCollaborate: _requestCollaborate,
        onJoin: _joinOpportunity,
        hasJoined: _hasJoined,
        joinLoading: _joinLoading,
        onDislike: () async {
          final uid = _currentUserId;
          if (uid == null || uid.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Log in to dislike posts'),
                behavior: SnackBarBehavior.floating,
              ));
            }
            return;
          }
          await _dao.toggleDislike(postId: post.id, userId: uid);
          await sl<ActivityLogDao>().logAction(
            userId: uid,
            action: post.isDislikedByMe ? 'undislike_post' : 'dislike_post',
            entityType: DatabaseSchema.tablePosts,
            entityId: post.id,
            metadata: {'author_id': post.authorId},
          );
          await _syncQueue.enqueue(
            operation: post.isDislikedByMe ? 'delete' : 'create',
            entity: 'dislikes',
            entityId: '${uid}_${post.id}',
            payload: {
              'user_id': uid,
              'post_id': post.id,
              'is_disliking': !post.isDislikedByMe,
              'author_id': post.authorId,
            },
          );
          unawaited(sl<SyncService>().processPendingSync());
          setState(() {
            final wasDisliked = post.isDislikedByMe;
            final wasLiked = post.isLikedByMe;
            _post = post.copyWith(
              isDislikedByMe: !wasDisliked,
              dislikeCount: wasDisliked
                  ? post.dislikeCount - 1
                  : post.dislikeCount + 1,
              // If disliking, remove like
              isLikedByMe: wasDisliked ? wasLiked : false,
              likeCount: (!wasDisliked && wasLiked)
                  ? post.likeCount - 1
                  : post.likeCount,
            );
          });
        },
        onLike: () async {
          final uid = _currentUserId;
          if (uid == null || uid.isEmpty) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Log in to like posts'),
                behavior: SnackBarBehavior.floating,
              ));
            }
            return;
          }
          await _dao.toggleLike(postId: post.id, userId: uid);
          await sl<ActivityLogDao>().logAction(
            userId: uid,
            action: post.isLikedByMe ? 'unlike_post' : 'like_post',
            entityType: DatabaseSchema.tablePosts,
            entityId: post.id,
            metadata: {'author_id': post.authorId},
          );
          debugPrint('[ProjectDetail] Local like toggle post=${post.id} user=$uid isLiking=${!post.isLikedByMe}');
          await _syncQueue.enqueue(
            operation: post.isLikedByMe ? 'delete' : 'create',
            entity: 'likes',
            entityId: '${uid}_${post.id}',
            payload: {
              'user_id': uid,
              'post_id': post.id,
              'is_liking': !post.isLikedByMe,
              'author_id': post.authorId,
              'actor_name': _currentUserName,
              'post_title': post.title,
            },
          );
          debugPrint('[ProjectDetail] Like queued post=${post.id} user=$uid isLiking=${!post.isLikedByMe}');
          unawaited(sl<SyncService>().processPendingSync());
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Hero image gallery
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _HeroGallery extends StatelessWidget {
  final List<String> urls;
  final int currentIndex;
  final ValueChanged<int> onPageChanged;
  final String title;

  const _HeroGallery({
    required this.urls,
    required this.currentIndex,
    required this.onPageChanged,
    required this.title,
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
          itemBuilder: (context, i) => GestureDetector(
            onTap: () {
              if (_isVideoUrl(urls[i])) {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => OfflineVideoPlayerScreen(
                      source: urls[i],
                      title: title,
                    ),
                  ),
                );
              }
            },
            child: _isVideoUrl(urls[i])
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Author snippet
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _AuthorSnippet extends StatelessWidget {
  final PostModel post;
  final bool isFollowing;
  final bool followLoading;
  final bool canFollow;
  final VoidCallback onFollow;
  final VoidCallback onAuthorTap;

  const _AuthorSnippet({
    required this.post,
    required this.isFollowing,
    required this.followLoading,
    required this.canFollow,
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
                      style: GoogleFonts.plusJakartaSans(
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
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 15, fontWeight: FontWeight.w700)),
                  Text(post.faculty ?? post.authorRole ?? '',
                    style: GoogleFonts.plusJakartaSans(
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
              onPressed: canFollow ? onFollow : null,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(0, 36),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                textStyle: GoogleFonts.plusJakartaSans(
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

class _CommentsSection extends StatelessWidget {
  final List<CommentRecord> comments;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final CommentRecord? replyingTo;
  final ValueChanged<CommentRecord> onReply;
  final VoidCallback onCancelReply;

  const _CommentsSection({
    required this.comments,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    required this.replyingTo,
    required this.onReply,
    required this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    // Separate top-level comments and replies
    final topLevel = comments
        .where((c) => c.parentCommentId == null)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final repliesByParent = <String, List<CommentRecord>>{};
    for (final c in comments.where((c) => c.parentCommentId != null)) {
      repliesByParent.putIfAbsent(c.parentCommentId!, () => []).add(c);
    }
    // Sort each reply list oldest-first
    for (final list in repliesByParent.values) {
      list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Comments',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),

          // Reply indicator
          if (replyingTo != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.reply, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Replying to ${replyingTo!.authorName ?? 'Unknown'}',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12, color: AppColors.primary),
                    ),
                  ),
                  GestureDetector(
                    onTap: onCancelReply,
                    child: const Icon(Icons.close, size: 16,
                        color: AppColors.textSecondaryLight),
                  ),
                ],
              ),
            ),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  decoration: InputDecoration(
                    hintText: replyingTo != null
                        ? 'Write a replyâ€¦'
                        : 'Write a comment',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton(
                onPressed: isSubmitting ? null : onSubmit,
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 48),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                ),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Post'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (comments.isEmpty)
            Text(
              'No comments yet. Start the discussion.',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                color: AppColors.textSecondaryLight,
              ),
            )
          else
            Column(
              children: topLevel.expand((comment) {
                final replies = repliesByParent[comment.id] ?? [];
                return [
                  _CommentTile(comment: comment, onReply: onReply),
                  ...replies.map((r) => Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: _CommentTile(comment: r, onReply: onReply,
                        isReply: true),
                  )),
                ];
              }).toList(),
            ),
        ],
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  final CommentRecord comment;
  final ValueChanged<CommentRecord> onReply;
  final bool isReply;

  const _CommentTile({
    required this.comment,
    required this.onReply,
    this.isReply = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isReply
            ? AppColors.primary.withValues(alpha: 0.04)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (isReply) ...[
                const Icon(Icons.subdirectory_arrow_right,
                    size: 14, color: AppColors.textSecondaryLight),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  comment.authorName ?? 'Unknown',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                timeago.format(comment.createdAt),
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 11,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            comment.content,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              height: 1.5,
              color: AppColors.textPrimaryLight,
            ),
          ),
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => onReply(comment),
            child: Text(
              'Reply',
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Stats grid
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StatsGrid extends StatelessWidget {
  final PostModel post;
  const _StatsGrid({required this.post});

  @override
  Widget build(BuildContext context) {
    final memberCount = post.joinCount;
    final stats = [
      ('Views', '${post.viewCount}', Icons.visibility_outlined),
      ('Likes', '${post.likeCount}', Icons.favorite_border_rounded),
      ('Comments', '${post.commentCount}', Icons.chat_bubble_outline_rounded),
      ('Members', '$memberCount', Icons.group_outlined),
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
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 14, fontWeight: FontWeight.w700,
                          color: AppColors.primary),
                        overflow: TextOverflow.ellipsis),
                      Text(label,
                        style: GoogleFonts.plusJakartaSans(
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Skills section
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8, runSpacing: 8,
            children: post.skillsUsed.map((s) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
              ),
              child: Text(s, style: GoogleFonts.plusJakartaSans(
                fontSize: 13, fontWeight: FontWeight.w500,
                color: AppColors.textSecondaryLight)),
            )).toList(),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Collaboration section
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 17, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text('HIRING',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10, fontWeight: FontWeight.w800,
                    color: AppColors.success, letterSpacing: 0.08)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '"Looking for collaborators to help bring this project to life."',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13, fontStyle: FontStyle.italic,
              color: AppColors.textSecondaryLight, height: 1.5),
          ),
          const SizedBox(height: 12),
          CollaboratorBubbles(
            photoUrls: const [null, null],
            totalCount: post.joinCount,
          ),
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

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// External links
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
            style: GoogleFonts.plusJakartaSans(fontSize: 17, fontWeight: FontWeight.w700)),
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
                style: GoogleFonts.plusJakartaSans(fontSize: 14, fontWeight: FontWeight.w500))),
              const Icon(Icons.open_in_new_rounded,
                  size: 16, color: AppColors.textSecondaryLight),
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Sticky bottom bar
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Opportunity metadata panel
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _OpportunityMeta extends StatelessWidget {
  final PostModel post;
  const _OpportunityMeta({required this.post});

  @override
  Widget build(BuildContext context) {
    final deadline = post.opportunityDeadline;
    final maxP = post.maxParticipants;
    final expertise = post.areaOfExpertise;
    final joinCount = post.joinCount;

    if (deadline == null && maxP == null && (expertise == null || expertise.isEmpty) && joinCount == 0) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.primaryTint10,
          borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Opportunity Details',
              style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 10),
            if (expertise != null && expertise.isNotEmpty)
              _MetaRow(
                icon: Icons.auto_awesome_rounded,
                label: 'Area of Expertise',
                value: expertise,
              ),
            if (deadline != null)
              _MetaRow(
                icon: Icons.event_rounded,
                label: 'Deadline',
                value: '${deadline.day}/${deadline.month}/${deadline.year}',
              ),
            if (maxP != null && maxP > 0)
              _MetaRow(
                icon: Icons.people_rounded,
                label: 'Max Participants',
                value: maxP.toString(),
              ),
            if (joinCount > 0)
              _MetaRow(
                icon: Icons.how_to_reg_rounded,
                label: 'Joined',
                value: '$joinCount ${joinCount == 1 ? 'person' : 'people'}',
              ),
          ],
        ),
      ),
    );
  }
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MetaRow({required this.icon, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Text('$label: ',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13, fontWeight: FontWeight.w600,
              color: AppColors.textSecondaryLight)),
          Expanded(
            child: Text(value,
              style: GoogleFonts.plusJakartaSans(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Sticky bottom action bar
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _StickyBar extends StatelessWidget {
  final PostModel post;
  final VoidCallback onLike;
  final VoidCallback onDislike;
  final VoidCallback onShare;
  final VoidCallback onCollaborate;
  final VoidCallback onJoin;
  final bool hasJoined;
  final bool joinLoading;

  const _StickyBar({
    required this.post,
    required this.onLike,
    required this.onDislike,
    required this.onShare,
    required this.onCollaborate,
    required this.onJoin,
    required this.hasJoined,
    required this.joinLoading,
  });

  @override
  Widget build(BuildContext context) {
    final isOpportunity = post.type == 'opportunity';
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
                style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDislike,
                icon: Icon(
                  post.isDislikedByMe
                      ? Icons.thumb_down_rounded
                      : Icons.thumb_down_outlined,
                  color: post.isDislikedByMe ? AppColors.warning : null,
                  size: 20,
                ),
                tooltip: 'Dislike',
              ),
              const SizedBox(width: 12),
              IconButton(
                onPressed: onShare,
                icon: const Icon(Icons.share_outlined),
                tooltip: 'Share',
              ),
              const SizedBox(width: 12),
              if (isOpportunity) ...[
                // Join / Leave button for opportunity posts
                Expanded(
                  child: joinLoading
                      ? const Center(
                          child: SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          ),
                        )
                      : ElevatedButton.icon(
                          onPressed: onJoin,
                          icon: Icon(
                            hasJoined
                                ? Icons.check_circle_rounded
                                : Icons.how_to_reg_rounded,
                            size: 18,
                          ),
                          label: Text(hasJoined ? 'Joined' : 'Join Opportunity'),
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            backgroundColor: hasJoined
                                ? AppColors.success
                                : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                if (post.joinCount > 0)
                  Text(
                    '${post.joinCount}',
                    style: GoogleFonts.plusJakartaSans(
                      fontWeight: FontWeight.w600, fontSize: 13),
                  ),
              ] else ...[
                // Collaborate button for project posts
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onCollaborate,
                    icon: const Icon(Icons.group_add_rounded, size: 18),
                    label: const Text('Collaborate'),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Glass UI helpers â€” AppBar overlays
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

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
