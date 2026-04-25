// lib/features/feed/screens/create_post_screen.dart
//
// MUST StarTrack â€” Create Post Screen (Phase 3)
//
// Matches create_project_post.html exactly:
//   â€¢ Title, description, category + faculty dropdowns
//   â€¢ Tag chip input (reuses SkillChipInput)
//   â€¢ Media upload area with upload progress indicator
//   â€¢ Visibility radio group (Public / Followers / Collaborators)
//   â€¢ Sticky bottom bar: Publish + save as draft
//
// HCI:
//   â€¢ Feedback: upload progress bar per file
//   â€¢ Constraints: publish blocked until title filled
//   â€¢ Affordance: dashed upload box signals droppable area
//   â€¢ Visibility of system status: compression % shown per file

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:async';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/router/route_names.dart';
import '../../../core/router/route_guards.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../data/local/dao/post_dao.dart';
import '../../../data/local/dao/sync_queue_dao.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/cloudinary_service.dart';
import '../../../data/remote/sync_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/hci_components/st_form_widgets.dart';
import '../bloc/feed_cubit.dart';
import 'my_projects_screen.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({
    super.key,
    this.existingPost,
    this.groupId,
    this.groupName,
    this.groupAvatarUrl,
  });

  final PostModel? existingPost;
  final String? groupId;
  final String? groupName;
  final String? groupAvatarUrl;

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _qualificationsCtrl = TextEditingController();
  final _deadlineCtrl = TextEditingController();
  final _youtubeCtrl = TextEditingController();

  String _category = 'Innovation';
  String? _faculty = 'Computing and Informatics';
  List<String> _selectedFaculties = [];
  String _type = 'project';
  PostVisibility _visibility = PostVisibility.public;
  List<String> _tags = [];
  final List<_UploadItem> _uploads = [];
  List<_LinkItem> _linkItems = [];
  String _qualifications = '';
  DateTime? _deadline;
  bool _publishing = false;

  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  bool get _isEditing => widget.existingPost != null;
  bool get _isGroupProject =>
      (widget.groupId?.isNotEmpty ?? false) || widget.existingPost?.groupId != null;

  static const int _maxFileSizeBytes = 50 * 1024 * 1024;
  static const int _maxImageSizeBytes = 1536 * 1024; // 1.5 MB

  static const _categories = ['Innovation', 'Research', 'Software', 'Design', 'Hardware', 'Data Analysis'];
  static const _faculties = [
    'Computing and Informatics', 'Applied Sciences and Technology',
    'Medicine', 'Business and Management Sciences', 'Science',
  ];
  static const _types = [
    ('project', 'Project', Icons.rocket_launch_rounded),
    ('opportunity', 'Opportunity', Icons.work_outline_rounded),
    ('advert', 'Advert', Icons.campaign_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _qualificationsCtrl.addListener(() => _qualifications = _qualificationsCtrl.text);
    _seedFromExistingPost();
    if (_isGroupProject) {
      _type = 'project';
      _visibility = PostVisibility.public;
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    _qualificationsCtrl.dispose();
    _deadlineCtrl.dispose();
    _youtubeCtrl.dispose();
    super.dispose();
  }

  void _seedFromExistingPost() {
    final post = widget.existingPost;
    if (post == null) {
      return;
    }

    _titleCtrl.text = post.title;
    _descCtrl.text = post.description ?? '';
    _category = _categories.contains(post.category) ? post.category! : _category;
    _faculty = post.faculty;
    _type = post.type;
    _visibility = post.visibility;
    _tags = _normalizeSkillTokens(post.tags);
    _linkItems = post.externalLinks.map((m) => _LinkItem(url: m['url'] ?? '', description: m['description'] ?? '')).toList();
    _qualifications = post.areaOfExpertise ??
      (post.skillsUsed.isNotEmpty ? post.skillsUsed.join(', ') : '');
    _qualificationsCtrl.text = _qualifications;
    _deadline = post.opportunityDeadline;
    // Seed multi-faculty selection for opportunities and adverts.
    if ((_type == 'opportunity' || _type == 'advert') && _faculty != null) {
      _selectedFaculties = _faculty!.split(', ').where((f) => f.isNotEmpty).toList();
    }
    _deadlineCtrl.text = _deadline != null ? '${_deadline!.year}-${_deadline!.month.toString().padLeft(2,'0')}-${_deadline!.day.toString().padLeft(2,'0')}' : '';
    _youtubeCtrl.text = post.youtubeUrl ?? '';
    _uploads.addAll(post.mediaUrls.map(_uploadItemFromSource));
  }

  List<String> _normalizeSkillTokens(Iterable<String> input) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final raw in input) {
      final fragments = raw.split(RegExp(r'[,;|\n\r]+'));
      for (final fragment in fragments) {
        final token = fragment.trim().replaceAll(RegExp(r'\s+'), ' ');
        if (token.isEmpty) {
          continue;
        }
        final key = token.toLowerCase();
        if (seen.add(key)) {
          normalized.add(token);
        }
      }
    }

    return normalized;
  }

  List<String> _normalizeSkillTokensFromText(String input) {
    if (input.trim().isEmpty) {
      return const [];
    }
    return _normalizeSkillTokens([input]);
  }

  String? _normalizeExpertiseText(String input) {
    final tokens = _normalizeSkillTokensFromText(input);
    if (tokens.isEmpty) {
      return null;
    }
    return tokens.join(', ');
  }

  Future<void> _pickMedia() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('Select Photos'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickPhotos();
              },
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Select Video'),
              onTap: () {
                Navigator.of(ctx).pop();
                _pickVideo();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickPhotos() async {
    try {
      final files = await _imagePicker.pickMultiImage(imageQuality: 80);
      if (files.isEmpty) return;
      await _addPickedFiles(files, isVideo: false);
    } on PlatformException {
      await _pickSinglePhotoFallback();
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 2),
      );
      if (file == null) return;
      await _addPickedFiles([file], isVideo: true);
    } on PlatformException {
      await _pickVideoWithImagePickerFallback();
    }
  }

  Future<void> _pickSinglePhotoFallback() async {
    final file = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (file == null) return;

    await _addPickedFiles([file], isVideo: false);
    _showPickerMessage(
      'Multi-photo selection is not supported on this device. Picked one photo instead.',
    );
  }

  Future<void> _pickVideoWithImagePickerFallback() async {
    final file = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 2),
    );
    if (file == null) return;
    await _addPickedFiles([file], isVideo: true);
    _showPickerMessage('Using compatibility video picker for this device.');
  }

  void _showPickerMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: AppColors.info,
      ),
    );
  }

  Future<void> _addPickedFiles(
    List<XFile> files, {
    required bool isVideo,
  }) async {
    final items = <_UploadItem>[];
    final rejected = <String>[];
    final unsupported = <String>[];

    for (final picked in files) {
      if (!isVideo && _isUnsupportedImageFormat(picked.name)) {
        unsupported.add(picked.name);
        continue;
      }

      final local = await _persistPickedFile(picked);
      if (local == null) {
        rejected.add(picked.name);
        continue;
      }
      final fileSize = await local.length();
      final sizeLimit = isVideo ? _maxFileSizeBytes : _maxImageSizeBytes;
      if (fileSize > sizeLimit) {
        await local.delete().catchError((_) => local);
        rejected.add(picked.name);
        continue;
      }
      items.add(_UploadItem(
        id: _uuid.v4(),
        file: local,
        source: local.path,
        name: picked.name,
        progress: 0,
        isVideo: isVideo,
      ));
    }

    if (!mounted) return;
    if (items.isNotEmpty) {
      setState(() => _uploads.addAll(items));
      unawaited(_startImmediateUploads(items));
    }
    if (unsupported.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${unsupported.length} image(s) use HEIC/HEIF, which this build cannot preview. Use JPG or PNG instead.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
    if (rejected.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${rejected.length} file(s) could not be prepared or exceeded 50MB and were skipped.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
    }
  }

  Future<void> _startImmediateUploads(List<_UploadItem> items) async {
    if (items.isEmpty || _type == 'opportunity') return;

    final wasOffline = await _isOffline();
    if (wasOffline || !sl<CloudinaryService>().isConfigured) {
      return;
    }

    final cloudinary = sl<CloudinaryService>();
    for (final item in items) {
      final localFile = item.file;
      if (localFile == null || !await localFile.exists()) {
        continue;
      }

      _setUploadState(item.id, isUploading: true, uploadFailed: false);
      try {
        final remoteUrl = await cloudinary.uploadFile(
          localFile,
          onProgress: (progress) => _setUploadProgress(item.id, progress),
        );
        _setUploadState(
          item.id,
          isUploading: false,
          uploadFailed: false,
          uploadedRemotely: true,
          progress: 1.0,
          source: remoteUrl,
        );
      } catch (error) {
        debugPrint('[CreatePost] Immediate upload failed for ${item.name}: $error');
        _setUploadState(
          item.id,
          isUploading: false,
          uploadFailed: true,
          progress: 0.0,
        );
      }
    }
  }

  bool _isUnsupportedImageFormat(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.heic') || lower.endsWith('.heif');
  }

  Future<File?> _persistPickedFile(XFile picked) async {
    try {
      final supportDir = await getApplicationSupportDirectory();
      final uploadDir = Directory('${supportDir.path}/pending_uploads');
      if (!await uploadDir.exists()) {
        await uploadDir.create(recursive: true);
      }

      final originalName = picked.name.isNotEmpty ? picked.name : _uuid.v4();
      final sanitizedName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final targetPath = '${uploadDir.path}/${_uuid.v4()}_$sanitizedName';
      final targetFile = File(targetPath);

      final sourcePath = picked.path;
      if (sourcePath.isNotEmpty) {
        final sourceFile = File(sourcePath);
        if (await sourceFile.exists()) {
          return sourceFile.copy(targetPath);
        }
      }

      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) {
        return null;
      }
      await targetFile.writeAsBytes(bytes, flush: true);
      return targetFile;
    } catch (_) {
      return null;
    }
  }

  Future<UserModel?> _resolvePublishingUser() async {
    // Primary: global AuthCubit state (set after login / registration).
    final fromCubit = sl<AuthCubit>().currentUser;
    if (fromCubit != null) {
      final userDao = sl<UserDao>();
      final existing = await userDao.getUserById(fromCubit.id);
      if (existing != null) return existing;
      await userDao.insertUser(fromCubit);
      return fromCubit;
    }

    // Fallback: the user authenticated via a screen that still uses a local
    // AuthCubit (e.g. register steps 1-2). Guards always store the uid.
    final uid = sl<RouteGuards>().currentUserId;
    if (uid == null || uid.isEmpty) return null;
    return sl<UserDao>().getUserById(uid);
  }

  Future<bool> _isOffline() async {
    if (sl.isRegistered<ConnectivityService>()) {
      return !(await sl<ConnectivityService>().checkConnectivity());
    }

    final result = await Connectivity().checkConnectivity();
    return !result.any((item) =>
        item == ConnectivityResult.wifi ||
        item == ConnectivityResult.mobile ||
        item == ConnectivityResult.ethernet);
  }

  void _setUploadProgress(
    String id,
    double progress, {
    String? source,
    File? file,
  }) {
    if (!mounted) return;
    setState(() {
      final index = _uploads.indexWhere((upload) => upload.id == id);
      if (index < 0) return;
      final current = _uploads[index];
      _uploads[index] = current.copyWith(
        progress: progress.clamp(0.0, 1.0),
        source: source,
        file: file,
      );
    });
  }

  void _setUploadState(
    String id, {
    bool? isUploading,
    bool? uploadFailed,
    bool? uploadedRemotely,
    double? progress,
    String? source,
  }) {
    if (!mounted) return;
    setState(() {
      final index = _uploads.indexWhere((upload) => upload.id == id);
      if (index < 0) return;
      final current = _uploads[index];
      _uploads[index] = current.copyWith(
        isUploading: isUploading,
        uploadFailed: uploadFailed,
        uploadedRemotely: uploadedRemotely,
        progress: progress,
        source: source,
      );
    });
  }

  Future<List<String>> _resolveMediaUrlsForPublish({
    required bool wasOffline,
  }) async {
    final initialUrls = _uploads.map((upload) => upload.source).toList();
    if (_type == 'opportunity' || _uploads.isEmpty) {
      return initialUrls;
    }
    if (wasOffline || !sl<CloudinaryService>().isConfigured) {
      return initialUrls;
    }

    final cloudinary = sl<CloudinaryService>();
    final resolvedUrls = <String>[];

    for (final upload in _uploads) {
      if (upload.uploadedRemotely) {
        _setUploadProgress(upload.id, 1.0);
        resolvedUrls.add(upload.source);
        continue;
      }

      if (!upload.hasLocalFile) {
        _setUploadProgress(upload.id, 1.0);
        resolvedUrls.add(upload.source);
        continue;
      }

      final localPath = upload.file?.path ??
          (upload.source.startsWith('file://')
              ? Uri.parse(upload.source).toFilePath()
              : upload.source);
      final localFile = File(localPath);
      if (!await localFile.exists()) {
        resolvedUrls.add(upload.source);
        continue;
      }

      try {
        final remoteUrl = await cloudinary.uploadFile(
          localFile,
          onProgress: (progress) => _setUploadProgress(upload.id, progress),
        );
        _setUploadProgress(upload.id, 1.0, source: remoteUrl);
        resolvedUrls.add(remoteUrl);
      } catch (error) {
        debugPrint('[CreatePost] Media upload failed for ${upload.name}: $error');
        _setUploadProgress(upload.id, 0.0);
        resolvedUrls.add(upload.source);
      }
    }

    return resolvedUrls;
  }

  Future<void> _publish() async {
    if (!_formKey.currentState!.validate()) return;
    final feedCubit = context.read<FeedCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final publishingUser = await _resolvePublishingUser();
    if (!mounted) return;
    if (publishingUser == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please sign in before publishing a post.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    if (_type == 'advert' && _selectedFaculties.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Select at least one target faculty (or All Faculties).'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }
    if (_type == 'advert' && _deadline == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Please set an advert deadline.'),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _publishing = true);

    final wasOffline = await _isOffline();
    final mediaUrls = await _resolveMediaUrlsForPublish(wasOffline: wasOffline);
    final now = DateTime.now();
    final normalizedTags = _normalizeSkillTokens(_tags);
    final normalizedOpportunitySkills =
      _normalizeSkillTokensFromText(_qualificationsCtrl.text);
    final normalizedSkillsUsed =
      _type == 'project' ? normalizedTags : (_type == 'opportunity' ? normalizedOpportunitySkills : const <String>[]);
    final normalizedAreaOfExpertise =
      _type == 'opportunity' ? _normalizeExpertiseText(_qualificationsCtrl.text) : null;
    final selectedAudience = _selectedFaculties.contains(_FacultyMultiSelect.allFacultiesLabel)
        ? _FacultyMultiSelect.allFacultiesLabel
        : (_selectedFaculties.isEmpty ? null : _selectedFaculties.join(', '));
    // Only project and advert posts by students need admin approval.
    // Opportunity and group posts go live immediately regardless of role.
    final requiresModeration = publishingUser.role == UserRole.student &&
        (_type == 'project' || _type == 'advert');
    final moderationStatus = requiresModeration
        ? ModerationStatus.pending
        : ModerationStatus.approved;

    final post = widget.existingPost?.copyWith(
          authorId: publishingUser.id,
          authorName: publishingUser.displayName,
          authorPhotoUrl: publishingUser.photoUrl,
          authorRole: publishingUser.role.name,
        groupId: widget.groupId ?? widget.existingPost?.groupId,
        groupName: widget.groupName ?? widget.existingPost?.groupName,
        groupAvatarUrl:
          widget.groupAvatarUrl ?? widget.existingPost?.groupAvatarUrl,
          type: _type,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _type == 'project' ? _category : (_type == 'advert' ? 'advert' : null),
          faculty: _type == 'project' ? _faculty : selectedAudience,
          tags: _type == 'project' ? normalizedTags : [],
          skillsUsed: normalizedSkillsUsed,
          youtubeUrl: _youtubeCtrl.text.trim().isNotEmpty ? _youtubeCtrl.text.trim() : null,
          visibility: _visibility,
          moderationStatus: moderationStatus,
          mediaUrls: _type == 'opportunity' ? [] : mediaUrls,
          externalLinks: _linkItems.map((l) => {'url': l.url, 'description': l.description}).toList(),
          areaOfExpertise: normalizedAreaOfExpertise,
          opportunityDeadline: (_type == 'opportunity' || _type == 'advert') ? _deadline : null,
          updatedAt: now,
        ) ??
        PostModel(
          id: _uuid.v4(),
          authorId: publishingUser.id,
          authorName: publishingUser.displayName,
          authorPhotoUrl: publishingUser.photoUrl,
          authorRole: publishingUser.role.name,
          groupId: widget.groupId,
          groupName: widget.groupName,
          groupAvatarUrl: widget.groupAvatarUrl,
          type: _type,
          title: _titleCtrl.text.trim(),
          description: _descCtrl.text.trim(),
          category: _type == 'project' ? _category : (_type == 'advert' ? 'advert' : null),
          faculty: _type == 'project' ? _faculty : selectedAudience,
          tags: _type == 'project' ? normalizedTags : [],
          skillsUsed: normalizedSkillsUsed,
          youtubeUrl: _youtubeCtrl.text.trim().isNotEmpty ? _youtubeCtrl.text.trim() : null,
          visibility: _visibility,
          moderationStatus: moderationStatus,
          mediaUrls: _type == 'opportunity' ? [] : mediaUrls,
          externalLinks: _linkItems.map((l) => {'url': l.url, 'description': l.description}).toList(),
          areaOfExpertise: normalizedAreaOfExpertise,
          opportunityDeadline: (_type == 'opportunity' || _type == 'advert') ? _deadline : null,
          createdAt: now,
          updatedAt: now,
        );

    await _cacheUploadedImages(mediaUrls);

    final result = _isEditing
        ? await _updateExistingPost(post, wasOffline: wasOffline)
        : await feedCubit.publishPost(post);
    if (!mounted) return;

    setState(() => _publishing = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          wasOffline && _uploads.any((upload) => upload.hasLocalFile)
              ? 'You are offline. Your post is saved on this device and will upload automatically when network returns.'
              : result.message,
        ),
        backgroundColor:
            result.syncedRemotely ? AppColors.success : AppColors.warning,
      ),
    );

    if (result.savedLocally) {
      MyProjectsScreen.invalidateCache();
      context.pop(true);
    }
  }

  Future<PublishPostResult> _updateExistingPost(
    PostModel post, {
    required bool wasOffline,
  }) async {
    try {
      await sl<PostDao>().updatePost(post);
      await sl<SyncQueueDao>().enqueue(
        operation: 'update',
        entity: 'posts',
        entityId: post.id,
        payload: post.toMap(),
      );

      final syncResult = await sl<SyncService>().processPendingSync();
      if (syncResult.failed == 0 && syncResult.remaining == 0) {
        return const PublishPostResult(
          savedLocally: true,
          syncedRemotely: true,
          message: 'Post updated successfully.',
        );
      }

      return PublishPostResult(
        savedLocally: true,
        syncedRemotely: false,
        message: wasOffline
            ? 'Changes saved locally and will sync when you are back online.'
            : 'Post updated. Changes will sync to the server shortly.',
      );
    } catch (error) {
      debugPrint('Update post error: $error');
      return const PublishPostResult(
        savedLocally: false,
        syncedRemotely: false,
        message: 'Could not update your post right now. Please try again.',
      );
    }
  }

  Future<void> _cacheUploadedImages(List<String> mediaUrls) async {
    if (!mounted || mediaUrls.isEmpty) {
      return;
    }

    for (final url in mediaUrls.where((url) => !isVideoMediaPath(url))) {
      try {
        if (isLocalMediaPath(url)) {
          await precacheImage(FileImage(File(url)), context);
        } else {
          await precacheImage(CachedNetworkImageProvider(url), context);
        }
      } catch (error) {
        debugPrint('[CreatePost] Failed to cache image $url: $error');
      }
    }
  }

  void _handleClose() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      context.pop();
      return;
    }
    context.go(RouteNames.home);
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: _handleClose,
          tooltip: 'Discard',
        ),
        title: Text(
          _isEditing
            ? (_isGroupProject
              ? 'Edit Group Project'
              : (_type == 'project'
                  ? 'Edit Project'
                  : (_type == 'opportunity' ? 'Edit Opportunity' : 'Edit Advert')))
            : (_isGroupProject
              ? 'New Group Project'
              : (_type == 'project'
                  ? 'New Project'
                  : (_type == 'opportunity' ? 'New Opportunity' : 'New Advert'))),
        ),
        actions: _isEditing
            ? const []
            : [
                TextButton(
                  onPressed: () {},
                  child: Text('Drafts',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
                ),
              ],
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_isGroupProject)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: AppColors.primaryTint10,
                      borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.groupName ?? widget.existingPost?.groupName ?? 'Group Project',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'This project will be published under the group identity and remain visible in the home feed.',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 12,
                            color: AppColors.textSecondaryLight,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              // Type selector
              if (!_isGroupProject) ...[
                const _SectionHeader('Post Type'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: _types.map((t) {
                      final (value, label, icon) = t;
                      final active = _type == value;
                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: value == 'project' ? 8 : 0),
                          child: GestureDetector(
                            onTap: () => setState(() => _type = value),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: active
                                    ? AppColors.primary
                                    : Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
                                border: Border.all(
                                  color: active ? AppColors.primary : AppColors.borderLight),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(icon, size: 18,
                                    color: active ? Colors.white : AppColors.textSecondaryLight),
                                  const SizedBox(width: 8),
                                  Text(label,
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 13, fontWeight: FontWeight.w600,
                                      color: active ? Colors.white : AppColors.textSecondaryLight)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],

              // â”€â”€ Details â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const _SectionHeader('Details'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StTextField(
                      label: _type == 'project'
                        ? 'Project Title'
                        : (_type == 'opportunity' ? 'Project Name' : 'Advert Title'),
                      hint: _type == 'project'
                        ? 'Enter a catchy name for your project'
                        : (_type == 'opportunity'
                          ? 'Name of the project needing help'
                          : 'Enter the advert title'),
                      controller: _titleCtrl,
                      textInputAction: TextInputAction.next,
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? 'Title is required.' : null,
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),
                    StTextField(
                      label: 'Description',
                      hint: 'What are you building? Explain the goals and impact...',
                      controller: _descCtrl,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                    ),
                    const SizedBox(height: AppDimensions.spacingMd),

                    if (_type == 'project') ...[
                      // Category + Faculty row
                      Row(
                        children: [
                          Expanded(
                            child: StDropdown<String>(
                              label: 'Category',
                              value: _category,
                              items: _categories.map((c) =>
                                DropdownMenuItem(value: c, child: Text(c, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setState(() => _category = v ?? _category),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: StDropdown<String>(
                              label: 'Faculty',
                              value: _faculty,
                              items: _faculties.map((f) =>
                                DropdownMenuItem(value: f, child: Text(f, overflow: TextOverflow.ellipsis))).toList(),
                              onChanged: (v) => setState(() => _faculty = v ?? _faculty),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),

                      // Tags
                      SkillChipInput(
                        label: 'Tags',
                        initialSkills: _tags,
                        onChanged: (t) => setState(() => _tags = t),
                      ),
                    ] else ...[
                      // Qualifications
                      if (_type == 'opportunity') ...[
                        StTextField(
                          label: 'Qualifications',
                          hint: 'Required skills or experience',
                          controller: _qualificationsCtrl,
                          maxLines: 3,
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: AppDimensions.spacingMd),
                      ],

                      // Faculty audience — multi-select for opportunities/adverts
                      _FacultyMultiSelect(
                        selectedFaculties: _selectedFaculties,
                        includeAllOption: _type == 'advert',
                        helperText: _type == 'advert'
                            ? 'Choose the faculties this advert should target, or select All Faculties.'
                            : 'Select one or more faculties this opportunity applies to.',
                        onChanged: (faculties) =>
                            setState(() => _selectedFaculties = faculties),
                      ),
                      const SizedBox(height: AppDimensions.spacingMd),

                      // Deadline
                      GestureDetector(
                        onTap: () async {
                          final date = await showDatePicker(
                            context: context,
                            initialDate: _deadline ?? DateTime.now().add(const Duration(days: 30)),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365)),
                          );
                          if (date != null) {
                            setState(() {
                              _deadline = date;
                              _deadlineCtrl.text = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
                            });
                          }
                        },
                        child: AbsorbPointer(
                          child: StTextField(
                            label: _type == 'advert' ? 'Advert Deadline' : 'Deadline',
                            hint: 'Select deadline date',
                            controller: _deadlineCtrl,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // â”€â”€ Media upload â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (_type != 'opportunity') ...[
                _SectionHeader(_type == 'advert' ? 'Advert Media' : 'Project Media'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _UploadArea(
                    onTap: _pickMedia,
                    items: _uploads,
                    onRemove: (id) => setState(() =>
                      _uploads.removeWhere((u) => u.id == id)),
                  ),
                ),
              ],

              // â”€â”€ Links â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              const _SectionHeader('Links'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _LinksArea(
                  onAdd: () => setState(() => _linkItems.add(_LinkItem())),
                  items: _linkItems,
                  onRemove: (id) => setState(() => _linkItems.removeWhere((l) => l.id == id)),
                ),
              ),

              // â”€â”€ YouTube URL â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: StTextField(
                  controller: _youtubeCtrl,
                  label: 'YouTube Video URL (optional)',
                  hint: 'https://youtube.com/watch?v=...',
                  prefixIcon: const Icon(Icons.play_circle_outline_rounded),
                ),
              ),

              // â”€â”€ Visibility â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
              if (!_isGroupProject) ...[
                const _SectionHeader('Privacy & Visibility'),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _VisibilityPicker(
                    value: _visibility,
                    onChanged: (v) => setState(() => _visibility = v),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),

      // â”€â”€ Sticky publish button â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: SafeArea(
          top: false,
          child: StButton(
            label: _isEditing
              ? (_isGroupProject
                ? 'Save Group Project'
                : (_type == 'project' ? 'Save Project Changes' : (_type == 'advert' ? 'Save Advert Changes' : 'Save Opportunity Changes')))
              : (_isGroupProject
                ? 'Publish Group Project'
                : (_type == 'project' ? 'Publish Project' : (_type == 'advert' ? 'Publish Advert' : 'Publish Opportunity'))),
            trailingIcon: Icons.rocket_launch_rounded,
            isLoading: _publishing,
            onPressed: _publish,
          ),
        ),
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Section header
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(title.toUpperCase(),
        style: GoogleFonts.plusJakartaSans(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryLight, letterSpacing: 0.1)),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Upload area
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _UploadItem {
  final String id;
  final File? file;
  final String source;
  final String name;
  final double progress; // 0.0 â†’ 1.0
  final bool isVideo;
  final bool isUploading;
  final bool uploadFailed;
  final bool uploadedRemotely;

  const _UploadItem({
    required this.id,
    required this.file,
    required this.source,
    required this.name,
    required this.progress,
    required this.isVideo,
    this.isUploading = false,
    this.uploadFailed = false,
    this.uploadedRemotely = false,
  });

  bool get hasLocalFile => file != null || isLocalMediaPath(source);

  _UploadItem copyWith({
    String? id,
    File? file,
    String? source,
    String? name,
    double? progress,
    bool? isVideo,
    bool? isUploading,
    bool? uploadFailed,
    bool? uploadedRemotely,
  }) {
    return _UploadItem(
      id: id ?? this.id,
      file: file ?? this.file,
      source: source ?? this.source,
      name: name ?? this.name,
      progress: progress ?? this.progress,
      isVideo: isVideo ?? this.isVideo,
      isUploading: isUploading ?? this.isUploading,
      uploadFailed: uploadFailed ?? this.uploadFailed,
      uploadedRemotely: uploadedRemotely ?? this.uploadedRemotely,
    );
  }
}

_UploadItem _uploadItemFromSource(String source) {
  final localPath = source.startsWith('file://')
      ? Uri.parse(source).toFilePath()
      : source;
  final localFile = isLocalMediaPath(source) ? File(localPath) : null;
  return _UploadItem(
    id: const Uuid().v4(),
    file: localFile,
    source: source,
    name: _displayNameForMediaSource(source),
    progress: isLocalMediaPath(source) ? 0 : 1,
    isVideo: isVideoMediaPath(source),
    uploadedRemotely: !isLocalMediaPath(source),
  );
}

String _displayNameForMediaSource(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null && uri.pathSegments.isNotEmpty) {
    return uri.pathSegments.last;
  }

  final segments = source.split(RegExp(r'[\\/]'));
  return segments.isNotEmpty ? segments.last : source;
}

class _LinkItem {
  final String id;
  String url;
  String description;

  _LinkItem({String? id, this.url = '', this.description = ''}) : id = id ?? const Uuid().v4();
}

class _UploadArea extends StatelessWidget {
  final VoidCallback onTap;
  final List<_UploadItem> items;
  final ValueChanged<String> onRemove;

  const _UploadArea({
    required this.onTap,
    required this.items,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Drop zone — modern card with subtle gradient accent
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.primaryTint10,
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.35),
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(AppDimensions.radiusLg),
            ),
            child: Column(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.cloud_upload_rounded,
                    size: 28,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tap to upload photos or videos',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'JPG, PNG, MP4 · Max 50 MB per file',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Upload items
        if (items.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...items.map((item) => _UploadRow(item: item, onRemove: onRemove)),
        ],
      ],
    );
  }
}

class _UploadRow extends StatelessWidget {
  final _UploadItem item;
  final ValueChanged<String> onRemove;

  const _UploadRow({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final isDone = item.uploadedRemotely || item.progress >= 1.0;
    final previewPath = item.file?.path ??
        (item.source.startsWith('file://')
            ? Uri.parse(item.source).toFilePath()
            : item.source);
    final statusLabel = item.isUploading
        ? 'Uploading...'
        : item.uploadFailed
            ? 'Upload paused'
            : isDone
                ? 'Uploaded'
                : item.hasLocalFile
                    ? 'Ready to upload'
                    : 'Attached';
    final statusColor = item.isUploading
        ? AppColors.warning
        : item.uploadFailed
            ? AppColors.danger
            : isDone
                ? AppColors.success
                : item.hasLocalFile
                    ? AppColors.info
                    : AppColors.primary;
    final progressValue = item.isUploading
        ? item.progress.clamp(0.0, 1.0)
        : isDone
            ? 1.0
            : 0.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56, height: 56,
              child: item.isVideo
                  ? Container(
                      color: AppColors.primaryTint10,
                      child: const Center(
                        child: Icon(Icons.videocam_rounded,
                            size: 28, color: AppColors.primary),
                      ),
                    )
                  : item.hasLocalFile
                    ? Image.file(File(previewPath), fit: BoxFit.cover)
                    : Image.network(item.source, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(width: 12),

          // Name + progress
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(item.name,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      statusLabel,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: statusColor),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 4,
                    backgroundColor: AppColors.borderLight,
                    valueColor: AlwaysStoppedAnimation(
                      item.uploadFailed
                          ? AppColors.danger
                          : isDone
                              ? AppColors.success
                              : AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: Icon(isDone ? Icons.delete_outline_rounded : Icons.close_rounded,
              color: AppColors.textSecondaryLight),
            onPressed: () => onRemove(item.id),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Links area
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _LinksArea extends StatelessWidget {
  final VoidCallback onAdd;
  final List<_LinkItem> items;
  final ValueChanged<String> onRemove;

  const _LinksArea({
    required this.onAdd,
    required this.items,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ...items.map((item) => _LinkRow(item: item, onRemove: onRemove)),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: onAdd,
          icon: const Icon(Icons.add_link),
          label: const Text('Add Link'),
        ),
      ],
    );
  }
}

class _LinkRow extends StatelessWidget {
  final _LinkItem item;
  final ValueChanged<String> onRemove;

  const _LinkRow({required this.item, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: AppColors.borderLight),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Column(
        children: [
          TextField(
            decoration: const InputDecoration(labelText: 'URL'),
            onChanged: (v) => item.url = v,
            controller: TextEditingController(text: item.url),
          ),
          const SizedBox(height: 8),
          TextField(
            decoration: const InputDecoration(labelText: 'Description'),
            onChanged: (v) => item.description = v,
            controller: TextEditingController(text: item.description),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: IconButton(
              icon: const Icon(Icons.close_rounded, color: AppColors.textSecondaryLight),
              onPressed: () => onRemove(item.id),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Visibility picker
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

// ─────────────────────────────────────────────────────────────────────────────
// Faculty multi-select (for opportunities)
// ─────────────────────────────────────────────────────────────────────────────

class _FacultyMultiSelect extends StatelessWidget {
  final List<String> selectedFaculties;
  final ValueChanged<List<String>> onChanged;
  final bool includeAllOption;
  final String helperText;

  const _FacultyMultiSelect({
    required this.selectedFaculties,
    required this.onChanged,
    this.includeAllOption = false,
    this.helperText = 'Select one or more faculties this opportunity applies to.',
  });

  static const String allFacultiesLabel = 'All Faculties';

  static const _faculties = [
    'Computing and Informatics',
    'Applied Sciences and Technology',
    'Medicine',
    'Business and Management Sciences',
    'Science',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Target Faculties',
          style: GoogleFonts.plusJakartaSans(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          helperText,
          style: GoogleFonts.plusJakartaSans(
            fontSize: 11,
            color: AppColors.textSecondaryLight,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (includeAllOption) allFacultiesLabel,
            ..._faculties,
          ].map((faculty) {
            final selected = selectedFaculties.contains(faculty);
            return FilterChip(
              label: Text(
                faculty,
                style: GoogleFonts.plusJakartaSans(fontSize: 12),
              ),
              selected: selected,
              selectedColor: AppColors.primaryTint10,
              checkmarkColor: AppColors.primary,
              side: BorderSide(
                color: selected ? AppColors.primary : AppColors.borderLight,
              ),
              onSelected: (checked) {
                final updated = List<String>.from(selectedFaculties);
                if (checked) {
                  if (faculty == allFacultiesLabel) {
                    updated
                      ..clear()
                      ..add(allFacultiesLabel);
                  } else {
                    updated.remove(allFacultiesLabel);
                    updated.add(faculty);
                  }
                } else {
                  updated.remove(faculty);
                }
                onChanged(updated);
              },
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _VisibilityPicker extends StatelessWidget {
  final PostVisibility value;
  final ValueChanged<PostVisibility> onChanged;

  const _VisibilityPicker({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final options = [
      (PostVisibility.public, 'Public', 'Visible to everyone in StarTrack', Icons.public_rounded),
      (PostVisibility.followers, 'Followers Only', 'Only people following you can view', Icons.group_rounded),
      (PostVisibility.collaborators, 'Collaborators Only', 'Invite-only project dashboard', Icons.handshake_rounded),
    ];

    return Column(
      children: options.map((opt) {
        final (vis, label, desc, icon) = opt;
        final isSelected = value == vis;

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: InkWell(
            onTap: () => onChanged(vis),
            borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                border: Border.all(
                  color: isSelected ? AppColors.primary : AppColors.borderLight,
                  width: isSelected ? 1.5 : 0.8,
                ),
                borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
              ),
              child: Row(
                children: [
                  Icon(icon,
                    color: isSelected ? AppColors.primary : AppColors.textSecondaryLight),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(desc,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 11, color: AppColors.textSecondaryLight)),
                      ],
                    ),
                  ),
                  Radio<PostVisibility>(
                    value: vis,
                    // ignore: deprecated_member_use
                    groupValue: value,
                    // ignore: deprecated_member_use
                    onChanged: (v) => onChanged(v!),
                    activeColor: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

