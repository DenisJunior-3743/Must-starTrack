// lib/features/feed/screens/create_post_screen.dart
//
// MUST StarTrack Ã¢â‚¬â€ Create Post Screen (Phase 3)
//
// Matches create_project_post.html exactly:
//   Ã¢â‚¬Â¢ Title, description, category + faculty dropdowns
//   Ã¢â‚¬Â¢ Tag chip input (reuses SkillChipInput)
//   Ã¢â‚¬Â¢ Media upload area with upload progress indicator
//   Ã¢â‚¬Â¢ Visibility radio group (Public / Followers / Collaborators)
//   Ã¢â‚¬Â¢ Sticky bottom bar: Publish + save as draft
//
// HCI:
//   Ã¢â‚¬Â¢ Feedback: upload progress bar per file
//   Ã¢â‚¬Â¢ Constraints: publish blocked until title filled
//   Ã¢â‚¬Â¢ Affordance: dashed upload box signals droppable area
//   Ã¢â‚¬Â¢ Visibility of system status: compression % shown per file

import 'package:cached_network_image/cached_network_image.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
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
import '../../../data/remote/project_validation_service.dart';
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
  final _opportunitySkillsTooltipKey = GlobalKey<TooltipState>();

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
  bool _hasShownOpportunitySkillsTip = false;
  bool _collectingProjectValidation = false;

  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  bool get _isEditing => widget.existingPost != null;
  bool get _isGroupProject =>
      (widget.groupId?.isNotEmpty ?? false) ||
      widget.existingPost?.groupId != null;

  static const int _maxFileSizeBytes = 50 * 1024 * 1024;
  static const int _maxImageSizeBytes = 1536 * 1024; // 1.5 MB

  static const _categories = [
    'Innovation',
    'Research',
    'Software',
    'Design',
    'Hardware',
    'Data Analysis'
  ];
  static const _faculties = [
    'Computing and Informatics',
    'Applied Sciences and Technology',
    'Medicine',
    'Business and Management Sciences',
    'Science',
  ];
  static const _types = [
    ('project', 'Project', Icons.rocket_launch_rounded),
    ('opportunity', 'Opportunity', Icons.work_outline_rounded),
    ('advert', 'Advert', Icons.campaign_outlined),
  ];

  @override
  void initState() {
    super.initState();
    _qualificationsCtrl
        .addListener(() => _qualifications = _qualificationsCtrl.text);
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
    _category =
        _categories.contains(post.category) ? post.category! : _category;
    _faculty = post.faculty;
    _type = post.type;
    _visibility = post.visibility;
    _tags = _normalizeSkillTokens(post.tags);
    _linkItems = post.externalLinks
        .map((m) =>
            _LinkItem(url: m['url'] ?? '', description: m['description'] ?? ''))
        .toList();
    _qualifications = post.areaOfExpertise ??
        (post.skillsUsed.isNotEmpty ? post.skillsUsed.join(', ') : '');
    _qualificationsCtrl.text = _qualifications;
    _deadline = post.opportunityDeadline;
    // Seed multi-faculty selection for opportunities and adverts.
    if ((_type == 'opportunity' || _type == 'advert') && _faculty != null) {
      _selectedFaculties =
          _faculty!.split(', ').where((f) => f.isNotEmpty).toList();
    }
    _deadlineCtrl.text = _deadline != null
        ? '${_deadline!.year}-${_deadline!.month.toString().padLeft(2, '0')}-${_deadline!.day.toString().padLeft(2, '0')}'
        : '';
    _youtubeCtrl.text = post.youtubeUrl ?? '';
    _uploads.addAll(post.mediaUrls.map(_uploadItemFromSource));
  }

  List<String> _normalizeSkillTokens(Iterable<String> input) {
    final normalized = <String>[];
    final seen = <String>{};

    for (final raw in input) {
      final fragments = raw.split(RegExp(r'[,;|\n\r]+'));
      for (final fragment in fragments) {
        final token = fragment
            .trim()
            .replaceAll('_', ' ')
            .replaceAll(RegExp(r'\s+'), ' ');
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

  void _showOpportunitySkillsTooltip() {
    if (_hasShownOpportunitySkillsTip) {
      return;
    }
    _hasShownOpportunitySkillsTip = true;
    _opportunitySkillsTooltipKey.currentState?.ensureTooltipVisible();
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
        debugPrint(
            '[CreatePost] Immediate upload failed for ${item.name}: $error');
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
      final sanitizedName =
          originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
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
        debugPrint(
            '[CreatePost] Media upload failed for ${upload.name}: $error');
        _setUploadProgress(upload.id, 0.0);
        resolvedUrls.add(upload.source);
      }
    }

    return resolvedUrls;
  }

  /// Shows a short preflight dialog telling the user what's about to happen.
  /// Returns true if the user wants to proceed, false/null otherwise.
  Future<bool> _showValidationPreflightDialog() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0E9F6E).withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.verified_outlined,
                    size: 34,
                    color: Color(0xFF0E9F6E),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'Project Approval Required',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Before your project goes live, it must pass a quick validation check.\n\n'
                  'You\'ll be asked a few short questions about your contribution, the academic purpose, and content safety.\n\n'
                  'This helps maintain the quality and integrity of the StarTrack community.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 13,
                    height: 1.55,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0E9F6E),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Proceed to Validation',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: TextButton(
                    onPressed: () => Navigator.of(ctx).pop(false),
                    style: TextButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Not Now',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    return confirmed == true;
  }

  Future<_ProjectValidationAnswers?> _collectProjectValidationAnswers() async {
    return Navigator.of(context).push<_ProjectValidationAnswers>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (ctx) => _ProjectValidationDialog(
          isGroupProject: _isGroupProject,
        ),
      ),
    );
  }

  Future<void> _publish() async {
    if (_collectingProjectValidation || _publishing) {
      return;
    }
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
          content:
              Text('Select at least one target faculty (or All Faculties).'),
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

    // Project validation is part of the project publishing flow for every
    // project. Moderation approval remains a separate student-only decision.
    final requiresModeration = publishingUser.role == UserRole.student &&
        (_type == 'project' || _type == 'advert');
    _ProjectValidationAnswers? validationAnswers;
    if (_type == 'project') {
      _collectingProjectValidation = true;
      try {
        final proceed = await _showValidationPreflightDialog();
        if (!mounted || !proceed) {
          _collectingProjectValidation = false;
          return;
        }
        validationAnswers = await _collectProjectValidationAnswers();
      } finally {
        _collectingProjectValidation = false;
      }
    }
    if (!mounted) return;
    if (_type == 'project' && validationAnswers == null) {
      return;
    }

    setState(() => _publishing = true);

    final wasOffline = await _isOffline();
    final mediaUrls = await _resolveMediaUrlsForPublish(wasOffline: wasOffline);
    final now = DateTime.now();
    final normalizedTags = _normalizeSkillTokens(_tags);
    final normalizedOpportunitySkills =
        _normalizeSkillTokensFromText(_qualificationsCtrl.text);
    final normalizedSkillsUsed = _type == 'project'
        ? normalizedTags
        : (_type == 'opportunity'
            ? normalizedOpportunitySkills
            : const <String>[]);
    final normalizedAreaOfExpertise = _type == 'opportunity'
        ? _normalizeExpertiseText(_qualificationsCtrl.text)
        : null;
    final selectedAudience = _selectedFaculties
            .contains(_FacultyMultiSelect.allFacultiesLabel)
        ? _FacultyMultiSelect.allFacultiesLabel
        : (_selectedFaculties.isEmpty ? null : _selectedFaculties.join(', '));
    final moderationStatus = requiresModeration
        ? ModerationStatus.pending
        : ModerationStatus.approved;

    var post = widget.existingPost?.copyWith(
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
          category: _type == 'project'
              ? _category
              : (_type == 'advert' ? 'advert' : null),
          faculty: _type == 'project' ? _faculty : selectedAudience,
          tags: _type == 'project' ? normalizedTags : [],
          skillsUsed: normalizedSkillsUsed,
          youtubeUrl: _youtubeCtrl.text.trim().isNotEmpty
              ? _youtubeCtrl.text.trim()
              : null,
          visibility: _visibility,
          moderationStatus: moderationStatus,
          mediaUrls: _type == 'opportunity' ? [] : mediaUrls,
          externalLinks: _linkItems
              .map((l) => {'url': l.url, 'description': l.description})
              .toList(),
          ownershipAnswers: validationAnswers?.ownership ??
              widget.existingPost?.ownershipAnswers,
          contentValidationAnswers: validationAnswers?.content ??
              widget.existingPost?.contentValidationAnswers,
          areaOfExpertise: normalizedAreaOfExpertise,
          opportunityDeadline:
              (_type == 'opportunity' || _type == 'advert') ? _deadline : null,
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
          category: _type == 'project'
              ? _category
              : (_type == 'advert' ? 'advert' : null),
          faculty: _type == 'project' ? _faculty : selectedAudience,
          tags: _type == 'project' ? normalizedTags : [],
          skillsUsed: normalizedSkillsUsed,
          youtubeUrl: _youtubeCtrl.text.trim().isNotEmpty
              ? _youtubeCtrl.text.trim()
              : null,
          visibility: _visibility,
          moderationStatus: moderationStatus,
          mediaUrls: _type == 'opportunity' ? [] : mediaUrls,
          externalLinks: _linkItems
              .map((l) => {'url': l.url, 'description': l.description})
              .toList(),
          ownershipAnswers: validationAnswers?.ownership ?? const {},
          contentValidationAnswers: validationAnswers?.content ?? const {},
          areaOfExpertise: normalizedAreaOfExpertise,
          opportunityDeadline:
              (_type == 'opportunity' || _type == 'advert') ? _deadline : null,
          createdAt: now,
          updatedAt: now,
        );

    if (requiresModeration && post.type == 'project') {
      post = await sl<ProjectValidationService>().reviewPendingPost(post);
    }

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
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
                      : (_type == 'opportunity'
                          ? 'Edit Opportunity'
                          : 'Edit Advert')))
              : (_isGroupProject
                  ? 'New Group Project'
                  : (_type == 'project'
                      ? 'New Project'
                      : (_type == 'opportunity'
                          ? 'New Opportunity'
                          : 'New Advert'))),
        ),
        actions: _isEditing ? const [] : [],
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
              top: -70,
              right: -70,
              child: _GlowBlob(size: 220, color: Color(0x332563EB)),
            ),
            const Positioned(
              bottom: -80,
              left: -90,
              child: _GlowBlob(size: 250, color: Color(0x221152D4)),
            ),
            Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.white.withValues(alpha: 0.84),
                          borderRadius: BorderRadius.circular(
                            AppDimensions.radiusLg,
                          ),
                          border: Border.all(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.12)
                                : AppColors.primary.withValues(alpha: 0.14),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color:
                                    AppColors.primary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(
                                    AppDimensions.radiusMd),
                              ),
                              child: const Icon(
                                Icons.auto_awesome_rounded,
                                color: AppColors.primary,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _isEditing
                                        ? 'Update your post'
                                        : 'Ready to share your work?',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 17,
                                      fontWeight: FontWeight.w800,
                                      color: isDark
                                          ? AppColors.textPrimaryDark
                                          : AppColors.textPrimaryLight,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Post now to get feedback and attract collaborators.',
                                    style: GoogleFonts.plusJakartaSans(
                                      fontSize: 12,
                                      color: isDark
                                          ? AppColors.textSecondaryDark
                                          : AppColors.textSecondaryLight,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_isGroupProject)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.white.withValues(alpha: 0.84),
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusLg),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.12)
                                  : AppColors.primary.withValues(alpha: 0.14),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.groupName ??
                                    widget.existingPost?.groupName ??
                                    'Group Project',
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
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight,
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
                                padding: EdgeInsets.only(
                                    right: value == 'project' ? 8 : 0),
                                child: GestureDetector(
                                  onTap: () => setState(() => _type = value),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 200),
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 12),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? AppColors.primary
                                          : (isDark
                                              ? Colors.white
                                                  .withValues(alpha: 0.06)
                                              : Colors.white
                                                  .withValues(alpha: 0.9)),
                                      borderRadius: BorderRadius.circular(
                                          AppDimensions.radiusMd),
                                      border: Border.all(
                                          color: active
                                              ? AppColors.primary
                                              : (isDark
                                                  ? Colors.white
                                                      .withValues(alpha: 0.12)
                                                  : AppColors.borderLight)),
                                    ),
                                    child: Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Flexible(
                                          child: FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  icon,
                                                  size: 18,
                                                  color: active
                                                      ? Colors.white
                                                      : AppColors
                                                          .textSecondaryLight,
                                                ),
                                                const SizedBox(width: 8),
                                                Text(
                                                  label,
                                                  style: GoogleFonts
                                                      .plusJakartaSans(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w600,
                                                    color: active
                                                        ? Colors.white
                                                        : (isDark
                                                            ? AppColors
                                                                .textSecondaryDark
                                                            : AppColors
                                                                .textSecondaryLight),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
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

                    // Ã¢â€â‚¬Ã¢â€â‚¬ Details Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                    const _SectionHeader('Details'),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        children: [
                          StTextField(
                            label: _type == 'project'
                                ? 'Project Title'
                                : (_type == 'opportunity'
                                    ? 'Project Name'
                                    : 'Advert Title'),
                            hint: _type == 'project'
                                ? 'Enter a catchy name for your project'
                                : (_type == 'opportunity'
                                    ? 'Name of the project needing help'
                                    : 'Enter the advert title'),
                            controller: _titleCtrl,
                            textInputAction: TextInputAction.next,
                            validator: (v) => (v == null || v.trim().isEmpty)
                                ? 'Title is required.'
                                : null,
                          ),
                          const SizedBox(height: AppDimensions.spacingMd),
                          StTextField(
                            label: 'Description',
                            hint:
                                'What are you building? Explain the goals and impact...',
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
                                    items: _categories
                                        .map((c) => DropdownMenuItem(
                                            value: c,
                                            child: Text(c,
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) => setState(
                                        () => _category = v ?? _category),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: StDropdown<String>(
                                    label: 'Faculty',
                                    value: _faculty,
                                    items: _faculties
                                        .map((f) => DropdownMenuItem(
                                            value: f,
                                            child: Text(f,
                                                overflow:
                                                    TextOverflow.ellipsis)))
                                        .toList(),
                                    onChanged: (v) => setState(
                                        () => _faculty = v ?? _faculty),
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
                              Tooltip(
                                key: _opportunitySkillsTooltipKey,
                                triggerMode: TooltipTriggerMode.manual,
                                showDuration: const Duration(seconds: 6),
                                waitDuration: Duration.zero,
                                preferBelow: false,
                                message:
                                    'Use underscores for multi-word skills, e.g. web_programming.',
                                child: StTextField(
                                  label: 'Qualifications',
                                  hint: 'Required skills or experience',
                                  helperText:
                                      'Tip: use underscore for multi-word skills, e.g. web_programming.',
                                  controller: _qualificationsCtrl,
                                  maxLines: 3,
                                  textInputAction: TextInputAction.next,
                                  onTap: _showOpportunitySkillsTooltip,
                                ),
                              ),
                              const SizedBox(height: AppDimensions.spacingMd),
                            ],

                            // Faculty audience â€” multi-select for opportunities/adverts
                            _FacultyMultiSelect(
                              selectedFaculties: _selectedFaculties,
                              includeAllOption: _type == 'advert',
                              helperText: _type == 'advert'
                                  ? 'Choose the faculties this advert should target, or select All Faculties.'
                                  : 'Select one or more faculties this opportunity applies to.',
                              onChanged: (faculties) => setState(
                                  () => _selectedFaculties = faculties),
                            ),
                            const SizedBox(height: AppDimensions.spacingMd),

                            // Deadline
                            GestureDetector(
                              onTap: () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: _deadline ??
                                      DateTime.now()
                                          .add(const Duration(days: 30)),
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now()
                                      .add(const Duration(days: 365)),
                                );
                                if (date != null) {
                                  setState(() {
                                    _deadline = date;
                                    _deadlineCtrl.text =
                                        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                                  });
                                }
                              },
                              child: AbsorbPointer(
                                child: StTextField(
                                  label: _type == 'advert'
                                      ? 'Advert Deadline'
                                      : 'Deadline',
                                  hint: 'Select deadline date',
                                  controller: _deadlineCtrl,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    // Ã¢â€â‚¬Ã¢â€â‚¬ Media upload Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                    if (_type != 'opportunity') ...[
                      _SectionHeader(
                          _type == 'advert' ? 'Advert Media' : 'Project Media'),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _UploadArea(
                          onTap: _pickMedia,
                          items: _uploads,
                          onRemove: (id) => setState(
                              () => _uploads.removeWhere((u) => u.id == id)),
                        ),
                      ),
                    ],

                    // Ã¢â€â‚¬Ã¢â€â‚¬ Links Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                    const _SectionHeader('Links'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _LinksArea(
                        onAdd: () =>
                            setState(() => _linkItems.add(_LinkItem())),
                        items: _linkItems,
                        onRemove: (id) => setState(
                            () => _linkItems.removeWhere((l) => l.id == id)),
                      ),
                    ),

                    // Ã¢â€â‚¬Ã¢â€â‚¬ YouTube URL Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      child: StTextField(
                        controller: _youtubeCtrl,
                        label: 'YouTube Video URL (optional)',
                        hint: 'https://youtube.com/watch?v=...',
                        prefixIcon:
                            const Icon(Icons.play_circle_outline_rounded),
                      ),
                    ),

                    // Ã¢â€â‚¬Ã¢â€â‚¬ Visibility Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬Ã¢â€â‚¬
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
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF101B32).withValues(alpha: 0.92)
              : Colors.white.withValues(alpha: 0.95),
          border: Border(
            top: BorderSide(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.10)
                  : AppColors.borderLight,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: StButton(
            label: _isEditing
                ? (_isGroupProject
                    ? 'Save Group Project'
                    : (_type == 'project'
                        ? 'Save Project Changes'
                        : (_type == 'advert'
                            ? 'Save Advert Changes'
                            : 'Save Opportunity Changes')))
                : (_isGroupProject
                    ? 'Publish Group Project'
                    : (_type == 'project'
                        ? 'Publish Project'
                        : (_type == 'advert'
                            ? 'Publish Advert'
                            : 'Publish Opportunity'))),
            trailingIcon: Icons.rocket_launch_rounded,
            isLoading: _publishing,
            onPressed: _publish,
          ),
        ),
      ),
    );
  }
}

// Section header
class _ProjectValidationAnswers {
  const _ProjectValidationAnswers({
    required this.ownership,
    required this.content,
  });

  final Map<String, String> ownership;
  final Map<String, String> content;
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(title.toUpperCase(),
          style: GoogleFonts.plusJakartaSans(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight,
              letterSpacing: 0.1)),
    );
  }
}

// Upload area

class _UploadItem {
  final String id;
  final File? file;
  final String source;
  final String name;
  final double progress; // 0.0 Ã¢â€ â€™ 1.0
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
  final localPath =
      source.startsWith('file://') ? Uri.parse(source).toFilePath() : source;
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

  _LinkItem({String? id, this.url = '', this.description = ''})
      : id = id ?? const Uuid().v4();
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: [
        // Drop zone â€” modern card with subtle gradient accent
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : AppColors.primaryTint10,
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
                  'JPG, PNG, MP4 Â· Max 50 MB per file',
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.borderLight,
        ),
        borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
      ),
      child: Row(
        children: [
          // Thumbnail
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: SizedBox(
              width: 56,
              height: 56,
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
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
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
                    valueColor: AlwaysStoppedAnimation(item.uploadFailed
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
            icon: Icon(
                isDone ? Icons.delete_outline_rounded : Icons.close_rounded,
                color: AppColors.textSecondaryLight),
            onPressed: () => onRemove(item.id),
          ),
        ],
      ),
    );
  }
}

// Links area

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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Theme.of(context).cardColor,
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : AppColors.borderLight,
        ),
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
              icon: const Icon(Icons.close_rounded,
                  color: AppColors.textSecondaryLight),
              onPressed: () => onRemove(item.id),
            ),
          ),
        ],
      ),
    );
  }
}

// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€
// Faculty multi-select (for opportunities)
// â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€â”€

class _FacultyMultiSelect extends StatelessWidget {
  final List<String> selectedFaculties;
  final ValueChanged<List<String>> onChanged;
  final bool includeAllOption;
  final String helperText;

  const _FacultyMultiSelect({
    required this.selectedFaculties,
    required this.onChanged,
    this.includeAllOption = false,
    this.helperText =
        'Select one or more faculties this opportunity applies to.',
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
            color: isDark
                ? AppColors.textSecondaryDark
                : AppColors.textSecondaryLight,
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
              backgroundColor:
                  isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
              side: BorderSide(
                color: selected
                    ? AppColors.primary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.12)
                        : AppColors.borderLight),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final options = [
      (
        PostVisibility.public,
        'Public',
        'Visible to everyone in StarTrack',
        Icons.public_rounded
      ),
      (
        PostVisibility.followers,
        'Followers Only',
        'Only people following you can view',
        Icons.group_rounded
      ),
      (
        PostVisibility.collaborators,
        'Collaborators Only',
        'Invite-only project dashboard',
        Icons.handshake_rounded
      ),
    ];

    return RadioGroup<PostVisibility>(
      groupValue: value,
      onChanged: (next) {
        if (next == null) return;
        onChanged(next);
      },
      child: Column(
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
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Theme.of(context).cardColor,
                  border: Border.all(
                    color: isSelected
                        ? AppColors.primary
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : AppColors.borderLight),
                    width: isSelected ? 1.5 : 0.8,
                  ),
                  borderRadius: BorderRadius.circular(AppDimensions.radiusSm),
                ),
                child: Row(
                  children: [
                    Icon(icon,
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.textSecondaryLight),
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
                                  fontSize: 11,
                                  color: isDark
                                      ? AppColors.textSecondaryDark
                                      : AppColors.textSecondaryLight)),
                        ],
                      ),
                    ),
                    Radio<PostVisibility>(
                      value: vis,
                      activeColor: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _GlowBlob extends StatelessWidget {
  const _GlowBlob({required this.size, required this.color});

  final double size;
  final Color color;

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
              spreadRadius: 24,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Project Validation Dialog
// Extracted to its own StatefulWidget so that all mutable state lives inside
// a proper State object — avoids the `'attached': is not true` render crash
// caused by local variables in a showDialog builder being reset on redraws.
// ─────────────────────────────────────────────────────────────────────────────

class _ProjectValidationDialog extends StatefulWidget {
  const _ProjectValidationDialog({required this.isGroupProject});
  final bool isGroupProject;

  @override
  State<_ProjectValidationDialog> createState() =>
      _ProjectValidationDialogState();
}

class _ProjectValidationDialogState extends State<_ProjectValidationDialog> {
  late final TextEditingController _contributionCtrl;
  late final TextEditingController _evidenceCtrl;
  late final TextEditingController _groupReasonCtrl;
  late final TextEditingController _academicProblemCtrl;
  late final TextEditingController _methodsCtrl;
  late final TextEditingController _outcomesCtrl;
  late final TextEditingController _safetyDetailsCtrl;
  final TextEditingController _evidenceLinkInputCtrl = TextEditingController();

  final List<PlatformFile> _evidenceFiles = [];
  final List<String> _evidenceLinks = [];

  late String _projectTypeChoice;
  String _sensitiveChoice = 'No sensitive content included';
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _projectTypeChoice =
        widget.isGroupProject ? 'Group project' : 'Individual project';
    _contributionCtrl = TextEditingController();
    _evidenceCtrl = TextEditingController();
    _groupReasonCtrl = TextEditingController();
    _academicProblemCtrl = TextEditingController();
    _methodsCtrl = TextEditingController();
    _outcomesCtrl = TextEditingController();
    _safetyDetailsCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _contributionCtrl.dispose();
    _evidenceCtrl.dispose();
    _groupReasonCtrl.dispose();
    _academicProblemCtrl.dispose();
    _methodsCtrl.dispose();
    _outcomesCtrl.dispose();
    _safetyDetailsCtrl.dispose();
    _evidenceLinkInputCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final contribution = _contributionCtrl.text.trim();
    final evidence = _evidenceCtrl.text.trim();
    final groupReason = _groupReasonCtrl.text.trim();
    final academicProblem = _academicProblemCtrl.text.trim();
    final methods = _methodsCtrl.text.trim();
    final outcomes = _outcomesCtrl.text.trim();
    final safetyDetails = _safetyDetailsCtrl.text.trim();

    final isGroup = _projectTypeChoice == 'Group project';
    final needsSafetyDetails =
        _sensitiveChoice != 'No sensitive content included';

    // Evidence is satisfied if any one of: text, files, or links is provided.
    final hasEvidenceText = evidence.length >= 12;
    final hasEvidenceFiles = _evidenceFiles.isNotEmpty;
    final hasEvidenceLinks = _evidenceLinks.isNotEmpty;
    final hasEvidence = hasEvidenceText || hasEvidenceFiles || hasEvidenceLinks;

    final required = <String>[
      contribution,
      academicProblem,
      methods,
      outcomes,
    ];
    if (isGroup) required.add(groupReason);
    if (needsSafetyDetails) required.add(safetyDetails);

    if (required.any((a) => a.length < 12) || !hasEvidence) {
      setState(() {
        _errorText = !hasEvidence
            ? 'Please provide evidence: describe it in the text box, attach a file, or add a link.'
            : 'Please provide enough detail in all visible required fields before submitting.';
      });
      return;
    }

    // Assemble evidence summary for AI analysis.
    final evidenceParts = <String>[
      if (evidence.isNotEmpty) evidence,
      if (_evidenceFiles.isNotEmpty)
        'Attached files: ${_evidenceFiles.map((f) => f.name).join(', ')}',
      if (_evidenceLinks.isNotEmpty) 'Links: ${_evidenceLinks.join(' | ')}',
    ];
    final evidenceSummary = evidenceParts.join('\n');

    if (!mounted) return;
    Navigator.of(context).pop(
      _ProjectValidationAnswers(
        ownership: {
          'Project type': _projectTypeChoice,
          'Personal contribution': contribution,
          'Contribution evidence': evidenceSummary,
          if (_evidenceFiles.isNotEmpty)
            'Evidence file paths':
                _evidenceFiles.map((f) => f.path ?? f.name).join(', '),
          if (_evidenceLinks.isNotEmpty)
            'Evidence links': _evidenceLinks.join(', '),
          if (isGroup) 'Group posting reason': groupReason,
        },
        content: {
          'Academic problem addressed': academicProblem,
          'Methods and tools used': methods,
          'Results and outcomes': outcomes,
          'Sensitive content status': _sensitiveChoice,
          'Sensitive content handling details':
              needsSafetyDetails ? safetyDetails : 'Not applicable',
        },
      ),
    );
  }

  Future<void> _pickEvidenceFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: [
        'jpg',
        'jpeg',
        'png',
        'gif',
        'webp',
        'mp4',
        'mov',
        'm4v',
        'webm',
        'pdf',
        'doc',
        'docx',
        'txt',
      ],
    );
    if (result == null || result.files.isEmpty) return;
    setState(() => _evidenceFiles.addAll(result.files));
  }

  void _addEvidenceLink() {
    final link = _evidenceLinkInputCtrl.text.trim();
    if (link.isEmpty) return;
    setState(() {
      _evidenceLinks.add(link);
      _evidenceLinkInputCtrl.clear();
    });
  }

  Widget _buildEvidenceAttachments() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final chipBg = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : AppColors.primary.withValues(alpha: 0.07);
    final panelBg = isDark
        ? Colors.white.withValues(alpha: 0.04)
        : Colors.white.withValues(alpha: 0.78);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : AppColors.primary.withValues(alpha: 0.14);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: panelBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.fact_check_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Supporting evidence',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Attach reports, screenshots, prototype media, or add links. Uploaded project media is also checked after publishing.',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11.5,
                          height: 1.35,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _pickEvidenceFiles,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.42),
                    ),
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.attach_file_rounded, size: 18),
                  label: Text(
                    'Attach files',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.mustGold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    'Images, docs, and short videos supported',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.mustGoldDark,
                    ),
                  ),
                ),
              ],
            ),
            if (_evidenceFiles.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _evidenceFiles.map((f) {
                  final lowerName = f.name.toLowerCase();
                  final isImage = ['jpg', 'jpeg', 'png', 'gif', 'webp']
                      .any((ext) => lowerName.endsWith(ext));
                  final isVideo = ['mp4', 'mov', 'm4v', 'webm']
                      .any((ext) => lowerName.endsWith(ext));
                  return Chip(
                    backgroundColor: chipBg,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    avatar: Icon(
                      isImage
                          ? Icons.image_outlined
                          : (isVideo
                              ? Icons.videocam_outlined
                              : Icons.description_outlined),
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      f.name,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () => setState(() => _evidenceFiles.remove(f)),
                  );
                }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: _evidenceLinkInputCtrl,
                    keyboardType: TextInputType.url,
                    decoration: InputDecoration(
                      hintText: 'Paste a link (GitHub, report, prototype…)',
                      hintStyle: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                      prefixIcon: const Icon(Icons.link_rounded, size: 18),
                      isDense: true,
                      filled: true,
                      fillColor: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                    ),
                    onSubmitted: (_) => _addEvidenceLink(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: _addEvidenceLink,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.add_link_rounded, size: 16),
                    label: Text(
                      'Add',
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            if (_evidenceLinks.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _evidenceLinks.map((link) {
                  final display =
                      link.length > 40 ? '${link.substring(0, 38)}...' : link;
                  return Chip(
                    backgroundColor: chipBg,
                    side: BorderSide(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                    avatar: const Icon(
                      Icons.link_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    label: Text(
                      display,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    deleteIcon: const Icon(Icons.close, size: 14),
                    onDeleted: () =>
                        setState(() => _evidenceLinks.remove(link)),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _promptField({
    required String question,
    required String hint,
    required TextEditingController controller,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            question,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
              filled: true,
              fillColor: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.white.withValues(alpha: 0.92),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.14)
                      : AppColors.borderLight,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : AppColors.borderLight,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 1.4,
                ),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required String subtitle,
    required Color accentColor,
    required Color lightTint,
    required IconData icon,
    required List<Widget> children,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? accentColor.withValues(alpha: 0.10) : lightTint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark
              ? accentColor.withValues(alpha: 0.45)
              : accentColor.withValues(alpha: 0.26),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accentColor, size: 20),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 15,
                        fontWeight: FontWeight.w900,
                        color: isDark ? Colors.white : accentColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 12,
                        height: 1.35,
                        color: isDark
                            ? AppColors.textSecondaryDark
                            : AppColors.textSecondaryLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Widget _choiceRow({
    required String label,
    required bool selected,
    required VoidCallback? onTap,
    String? subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final activeBorder = AppColors.primary.withValues(alpha: 0.42);
    final inactiveBorder =
        isDark ? Colors.white.withValues(alpha: 0.14) : AppColors.borderLight;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primary.withValues(alpha: 0.08)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : Colors.white.withValues(alpha: 0.8)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? activeBorder : inactiveBorder,
              width: selected ? 1.2 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Icon(
                  selected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                  size: 19,
                  color: selected
                      ? AppColors.primary
                      : (isDark
                          ? AppColors.textSecondaryDark
                          : AppColors.textSecondaryLight),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.plusJakartaSans(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 11,
                          color: isDark
                              ? AppColors.textSecondaryDark
                              : AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isGroup = _projectTypeChoice == 'Group project';
    final needsSafetyDetails =
        _sensitiveChoice != 'No sensitive content included';

    return Scaffold(
      backgroundColor:
          isDark ? const Color(0xFF0B1222) : const Color(0xFFF1F6FF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardHeight =
                (constraints.maxHeight - 20).clamp(320.0, 860.0).toDouble();

            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 980),
                child: SizedBox(
                  height: cardHeight,
                  child: Container(
                    margin: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: isDark
                            ? const [Color(0xFF0F172A), Color(0xFF111C34)]
                            : const [Color(0xFFF8FBFF), Color(0xFFEAF2FF)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                    child: Column(
                      children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.04)
                                : Colors.white.withValues(alpha: 0.82),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(24),
                            ),
                            border: Border(
                              bottom: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.10)
                                    : AppColors.primary.withValues(alpha: 0.10),
                              ),
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 48,
                                height: 48,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0E9F6E)
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: const Icon(
                                  Icons.verified_outlined,
                                  color: Color(0xFF0E9F6E),
                                  size: 27,
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Project Validation',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 19,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      'AI checks ownership, academic value, media evidence, and safety before the admin approval queue.',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 12,
                                        height: 1.35,
                                        color: isDark
                                            ? AppColors.textSecondaryDark
                                            : AppColors.textSecondaryLight,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _sectionCard(
                                  title: 'Project Ownership',
                                  subtitle:
                                      'Tell us what you built and how to verify it.',
                                  accentColor: AppColors.primary,
                                  lightTint: const Color(0xFFEFF5FF),
                                  icon: Icons.workspace_premium_outlined,
                                  children: [
                                    Text(
                                      'Project type',
                                      style: GoogleFonts.plusJakartaSans(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    _choiceRow(
                                      label: 'Individual project',
                                      selected: _projectTypeChoice ==
                                          'Individual project',
                                      onTap: widget.isGroupProject
                                          ? null
                                          : () => setState(() {
                                                _projectTypeChoice =
                                                    'Individual project';
                                              }),
                                    ),
                                    _choiceRow(
                                      label: 'Group project',
                                      selected:
                                          _projectTypeChoice == 'Group project',
                                      subtitle: widget.isGroupProject
                                          ? 'Locked because this post is created from a group space.'
                                          : null,
                                      onTap: widget.isGroupProject
                                          ? null
                                          : () => setState(() {
                                                _projectTypeChoice =
                                                    'Group project';
                                              }),
                                    ),
                                    const SizedBox(height: 10),
                                    _promptField(
                                      question:
                                          'What exact parts did you personally create, research, design, test, or document?',
                                      hint:
                                          'Describe your specific contributions in detail.',
                                      controller: _contributionCtrl,
                                    ),
                                    _promptField(
                                      question:
                                          'What evidence supports your contribution? Describe links, reports, prototypes, or fieldwork references - or use the attachment tools below.',
                                      hint:
                                          'Briefly describe your evidence (optional if you attach files or links below).',
                                      controller: _evidenceCtrl,
                                    ),
                                    _buildEvidenceAttachments(),
                                    if (isGroup)
                                      _promptField(
                                        question:
                                            'Why is this group project posted from this account or group space?',
                                        hint:
                                            'Explain account ownership and publishing context.',
                                        controller: _groupReasonCtrl,
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                _sectionCard(
                                  title: 'Content Validation',
                                  subtitle:
                                      'Confirm the academic value and safety of this post.',
                                  accentColor:
                                      const Color.fromARGB(255, 18, 219, 45),
                                  lightTint: const Color(0xFFECFDF5),
                                  icon: Icons.psychology_alt_outlined,
                                  children: [
                                    _promptField(
                                      question:
                                          'What academic problem, course objective, research question, or practical skill does this project address?',
                                      hint:
                                          'Describe the academic goal or problem being solved.',
                                      controller: _academicProblemCtrl,
                                    ),
                                    _promptField(
                                      question:
                                          'Which methods, tools, materials, datasets, procedures, or technologies did you use?',
                                      hint:
                                          'List the process, tools, datasets, and technologies used.',
                                      controller: _methodsCtrl,
                                    ),
                                    _promptField(
                                      question:
                                          'What are the main results, learning outcomes, or collaboration value?',
                                      hint:
                                          'Summarize results, impact, and what was learned.',
                                      controller: _outcomesCtrl,
                                    ),
                                    const SizedBox(height: 6),
                                    _choiceRow(
                                      label: 'No sensitive content included',
                                      selected: _sensitiveChoice ==
                                          'No sensitive content included',
                                      onTap: () => setState(() {
                                        _sensitiveChoice =
                                            'No sensitive content included';
                                      }),
                                    ),
                                    _choiceRow(
                                      label:
                                          'Contains sensitive content and properly handled',
                                      selected: _sensitiveChoice ==
                                          'Contains sensitive content and properly handled',
                                      onTap: () => setState(() {
                                        _sensitiveChoice =
                                            'Contains sensitive content and properly handled';
                                      }),
                                    ),
                                    _choiceRow(
                                      label: 'Not sure',
                                      selected: _sensitiveChoice == 'Not sure',
                                      onTap: () => setState(() {
                                        _sensitiveChoice = 'Not sure';
                                      }),
                                    ),
                                    if (needsSafetyDetails)
                                      _promptField(
                                        question:
                                            'Describe how the content is handled safely and remains policy-compliant.',
                                        hint:
                                            'Explain moderation, consent, anonymization, and safeguards.',
                                        controller: _safetyDetailsCtrl,
                                      ),
                                  ],
                                ),
                                if (_errorText != null) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    _errorText!,
                                    style: GoogleFonts.plusJakartaSans(
                                      color: AppColors.danger,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.fromLTRB(20, 14, 20, 18),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.03)
                                : Colors.white.withValues(alpha: 0.72),
                            borderRadius: const BorderRadius.vertical(
                              bottom: Radius.circular(24),
                            ),
                            border: Border(
                              top: BorderSide(
                                color: isDark
                                    ? Colors.white.withValues(alpha: 0.08)
                                    : AppColors.borderLight,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Your answers are saved with the post and shown to admins with the AI review.',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: GoogleFonts.plusJakartaSans(
                                    fontSize: 11,
                                    height: 1.35,
                                    color: isDark
                                        ? AppColors.textSecondaryDark
                                        : AppColors.textSecondaryLight,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              TextButton(
                                onPressed: () {
                                  if (mounted) Navigator.of(context).pop();
                                },
                                child: const Text('Cancel'),
                              ),
                              const SizedBox(width: 8),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF0E9F6E),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 13,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                icon: const Icon(Icons.check_rounded, size: 18),
                                label: const Text('Submit'),
                                onPressed: _submit,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
