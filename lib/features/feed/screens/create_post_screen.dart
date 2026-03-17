// lib/features/feed/screens/create_post_screen.dart
//
// MUST StarTrack — Create Post Screen (Phase 3)
//
// Matches create_project_post.html exactly:
//   • Title, description, category + faculty dropdowns
//   • Tag chip input (reuses SkillChipInput)
//   • Media upload area with upload progress indicator
//   • Visibility radio group (Public / Followers / Collaborators)
//   • Sticky bottom bar: Publish + save as draft
//
// HCI:
//   • Feedback: upload progress bar per file
//   • Constraints: publish blocked until title filled
//   • Affordance: dashed upload box signals droppable area
//   • Visibility of system status: compression % shown per file

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'dart:io';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/constants/app_enums.dart';
import '../../../core/di/injection_container.dart';
import '../../../data/local/dao/user_dao.dart';
import '../../../data/models/post_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/remote/cloudinary_service.dart';
import '../../auth/bloc/auth_cubit.dart';
import '../../shared/hci_components/st_form_widgets.dart';
import '../bloc/feed_cubit.dart';

class CreatePostScreen extends StatefulWidget {
  const CreatePostScreen({super.key});

  @override
  State<CreatePostScreen> createState() => _CreatePostScreenState();
}

class _CreatePostScreenState extends State<CreatePostScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  String _category = 'Innovation';
  String _faculty = 'Computing and Informatics';
  String _type = 'project';
  PostVisibility _visibility = PostVisibility.public;
  List<String> _tags = [];
  final List<_UploadItem> _uploads = [];
  bool _publishing = false;

  final _imagePicker = ImagePicker();
  final _uuid = const Uuid();

  static const int _maxFileSizeBytes = 50 * 1024 * 1024;

  static const _categories = ['Innovation', 'Research', 'Software', 'Design', 'Hardware', 'Data Analysis'];
  static const _faculties = [
    'Computing and Informatics', 'Applied Sciences and Technology',
    'Medicine', 'Business and Management Sciences', 'Science',
  ];
  static const _types = [
    ('project', 'Project', Icons.rocket_launch_rounded),
    ('opportunity', 'Opportunity', Icons.work_outline_rounded),
  ];

  CloudinaryService? get _cloudinaryServiceOrNull {
    if (!sl.isRegistered<CloudinaryService>()) {
      return null;
    }
    return sl<CloudinaryService>();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
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
      final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
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
    final file = await _imagePicker.pickVideo(source: ImageSource.gallery);
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
      if (fileSize > _maxFileSizeBytes) {
        await local.delete().catchError((_) => local);
        rejected.add(picked.name);
        continue;
      }
      items.add(_UploadItem(
        id: _uuid.v4(),
        file: local,
        name: picked.name,
        progress: 0,
        isVideo: isVideo,
      ));
    }

    if (!mounted) return;
    if (items.isNotEmpty) {
      setState(() => _uploads.addAll(items));
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

  void _setUploadProgress(String id, double progress) {
    if (!mounted) return;
    setState(() {
      final index = _uploads.indexWhere((item) => item.id == id);
      if (index == -1) return;
      _uploads[index] = _uploads[index].copyWith(
        progress: progress.clamp(0, 1),
      );
    });
  }

  Future<List<String>> _uploadMediaToCloudinary() async {
    final cloudinaryService = _cloudinaryServiceOrNull;
    if (cloudinaryService == null) {
      throw Exception('Cloudinary service is unavailable.');
    }

    final urls = <String>[];
    for (final upload in _uploads) {
      if (!await upload.file.exists()) {
        throw Exception('Prepared upload file is missing: ${upload.file.path}');
      }
      _setUploadProgress(upload.id, 0);
      final url = await cloudinaryService.uploadFile(
        upload.file,
        onProgress: (fraction) => _setUploadProgress(upload.id, fraction),
      );
      urls.add(url);
      _setUploadProgress(upload.id, 1);
    }
    return urls;
  }

  Future<UserModel?> _resolvePublishingUser() async {
    final currentUser = sl<AuthCubit>().currentUser;
    if (currentUser == null) {
      return null;
    }

    final userDao = sl<UserDao>();
    final existing = await userDao.getUserById(currentUser.id);
    if (existing != null) {
      return existing;
    }

    await userDao.insertUser(currentUser);
    return currentUser;
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

    final cloudinaryService = _cloudinaryServiceOrNull;
    if (_uploads.isNotEmpty &&
        (cloudinaryService == null || !cloudinaryService.isConfigured)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Media upload is not configured. Set Cloudinary values in cloudinary_config.dart.',
          ),
          backgroundColor: AppColors.warning,
        ),
      );
      return;
    }

    setState(() => _publishing = true);

    List<String> mediaUrls = const [];
    try {
      if (_uploads.isNotEmpty) {
        mediaUrls = await _uploadMediaToCloudinary();
      }
    } catch (error, stackTrace) {
      debugPrint('[CreatePost] Media upload failed: $error');
      debugPrintStack(
        label: '[CreatePost] Media upload stack',
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not upload media: $error'),
          backgroundColor: AppColors.danger,
        ),
      );
      setState(() => _publishing = false);
      return;
    }

    final post = PostModel(
      id: _uuid.v4(),
      authorId: publishingUser.id,
      authorName: publishingUser.displayName,
      authorPhotoUrl: publishingUser.photoUrl,
      authorRole: publishingUser.role.name,
      type: _type,
      title: _titleCtrl.text.trim(),
      description: _descCtrl.text.trim(),
      category: _category,
      faculty: _faculty,
      tags: _tags,
      skillsUsed: const [],
      visibility: _visibility,
      mediaUrls: mediaUrls,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await _cacheUploadedImages(mediaUrls);

    final result = await feedCubit.publishPost(post);
    if (!mounted) return;

    setState(() => _publishing = false);

    messenger.showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor:
            result.syncedRemotely ? AppColors.success : AppColors.warning,
      ),
    );

    if (result.savedLocally) {
      context.pop();
    }
  }

  Future<void> _cacheUploadedImages(List<String> mediaUrls) async {
    if (!mounted || mediaUrls.isEmpty) {
      return;
    }

    for (final url in mediaUrls.where((url) => !_isVideoUrl(url))) {
      try {
        await precacheImage(CachedNetworkImageProvider(url), context);
      } catch (error) {
        debugPrint('[CreatePost] Failed to cache image $url: $error');
      }
    }
  }

  bool _isVideoUrl(String url) {
    final lower = url.toLowerCase();
    return lower.contains('/video/upload/') ||
        lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.3gp') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.mkv');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => context.pop(),
          tooltip: 'Discard',
        ),
        title: Text(_type == 'project' ? 'New Project' : 'New Opportunity'),
        actions: [
          TextButton(
            onPressed: () {}, //  save as draft
            child: Text('Drafts',
              style: GoogleFonts.lexend(
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
              // ── Type selector ──────────────────────────────────────────
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
                                  style: GoogleFonts.lexend(
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

              // ── Project details ────────────────────────────────────────
              const _SectionHeader('Project Details'),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    StTextField(
                      label: 'Project Title',
                      hint: 'Enter a catchy name for your project',
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
                      onChanged: (t) => setState(() => _tags = t),
                    ),
                  ],
                ),
              ),

              // ── Media upload ───────────────────────────────────────────
              const _SectionHeader('Project Media'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _UploadArea(
                  onTap: _pickMedia,
                  items: _uploads,
                  onRemove: (id) => setState(() =>
                    _uploads.removeWhere((u) => u.id == id)),
                ),
              ),

              // ── Visibility ─────────────────────────────────────────────
              const _SectionHeader('Privacy & Visibility'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _VisibilityPicker(
                  value: _visibility,
                  onChanged: (v) => setState(() => _visibility = v),
                ),
              ),
            ],
          ),
        ),
      ),

      // ── Sticky publish button ──────────────────────────────────────────
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          border: const Border(top: BorderSide(color: AppColors.borderLight)),
        ),
        child: SafeArea(
          top: false,
          child: StButton(
            label: _type == 'project' ? 'Publish Project' : 'Publish Opportunity',
            trailingIcon: Icons.rocket_launch_rounded,
            isLoading: _publishing,
            onPressed: _publish,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section header
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      child: Text(title.toUpperCase(),
        style: GoogleFonts.lexend(
          fontSize: 11, fontWeight: FontWeight.w700,
          color: AppColors.textSecondaryLight, letterSpacing: 0.1)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upload area
// ─────────────────────────────────────────────────────────────────────────────

class _UploadItem {
  final String id;
  final File file;
  final String name;
  final double progress; // 0.0 → 1.0
  final bool isVideo;

  const _UploadItem({
    required this.id,
    required this.file,
    required this.name,
    required this.progress,
    required this.isVideo,
  });

  _UploadItem copyWith({
    String? id,
    File? file,
    String? name,
    double? progress,
    bool? isVideo,
  }) {
    return _UploadItem(
      id: id ?? this.id,
      file: file ?? this.file,
      name: name ?? this.name,
      progress: progress ?? this.progress,
      isVideo: isVideo ?? this.isVideo,
    );
  }
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
        // Drop zone
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border.all(
                color: AppColors.borderLight, width: 2,
                style: BorderStyle.solid),
              borderRadius: BorderRadius.circular(AppDimensions.radiusMd),
            ),
            child: Column(
              children: [
                const Icon(Icons.cloud_upload_rounded,
                    size: 40, color: AppColors.primary),
                const SizedBox(height: 8),
                Text('Upload Photos or Videos',
                  style: GoogleFonts.lexend(fontWeight: FontWeight.w600)),
                Text('Maximum file size: 50MB',
                  style: GoogleFonts.lexend(
                    fontSize: 12, color: AppColors.textSecondaryLight)),
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
    final isDone = item.progress >= 1.0;

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
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              width: 48, height: 48,
              child: item.isVideo
                  ? Container(
                      color: AppColors.primaryTint10,
                      child: const Icon(Icons.videocam_rounded,
                          color: AppColors.primary))
                  : Image.file(item.file, fit: BoxFit.cover),
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
                        style: GoogleFonts.lexend(
                          fontSize: 12, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      isDone ? 'Uploaded' : 'Uploading…',
                      style: GoogleFonts.lexend(
                        fontSize: 10, fontWeight: FontWeight.w700,
                        color: isDone ? AppColors.success : AppColors.warning),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
                  child: LinearProgressIndicator(
                    value: item.progress,
                    minHeight: 4,
                    backgroundColor: AppColors.borderLight,
                    valueColor: AlwaysStoppedAnimation(
                      isDone ? AppColors.primary : AppColors.warning),
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

// ─────────────────────────────────────────────────────────────────────────────
// Visibility picker
// ─────────────────────────────────────────────────────────────────────────────

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
                          style: GoogleFonts.lexend(
                            fontSize: 14, fontWeight: FontWeight.w600)),
                        Text(desc,
                          style: GoogleFonts.lexend(
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
