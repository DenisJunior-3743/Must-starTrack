import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart' hide PickedFile;
import 'package:open_filex/open_filex.dart';
import 'package:record/record.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/di/injection_container.dart';
import '../../../core/router/route_names.dart';
import '../../../data/remote/firestore_service.dart';
import '../../../data/local/dao/message_dao.dart';
import '../bloc/message_cubit.dart';

class ChatDetailScreen extends StatefulWidget {
  const ChatDetailScreen({super.key});

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen> {
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _audioPlayer = AudioPlayer();

  Timer? _recordTicker;
  DateTime? _recordStartedAt;
  String? _recordFilePath;
  bool _isRecording = false;
  bool _isStoppingRecording = false;
  bool _recordingLocked = false;
  bool _willCancelRecording = false;
  double _recordDragDy = 0;
  double _recordWavePhase = 0;
  Duration _recordingDuration = Duration.zero;

  String? _playingMessageId;
  String? _activeAudioMessageId;
  Duration _playbackPosition = Duration.zero;
  Duration _playbackDuration = Duration.zero;
  double _playbackSpeed = 1.0;
  int _audioPlaybackRequestId = 0;

  bool _hasText = false;
  File? _pendingAttachment;
  String? _pendingAttachmentType;
  String? _pendingAttachmentName;

  MessageModel? _replyToMessage;
  String? _replyToSenderLabel;

  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  StreamSubscription<UserDevicePresenceSummary>? _peerPresenceSub;
  final _firestore = sl<FirestoreService>();

  String? _peerStatusText;
  bool _peerActiveRecently = false;
  String? _lastLoadedPeerId;

  @override
  void initState() {
    super.initState();
    _msgCtrl.addListener(_onTextChanged);

    _playerStateSub = _audioPlayer.playerStateStream.listen((state) {
      if (!mounted) {
        return;
      }
      if (state.processingState == ProcessingState.completed) {
        setState(() {
          _playingMessageId = null;
          _playbackPosition = _playbackDuration;
        });
      }
    });

    _positionSub = _audioPlayer.positionStream.listen((position) {
      if (!mounted) {
        return;
      }
      setState(() {
        _playbackPosition = position;
      });
    });

    _durationSub = _audioPlayer.durationStream.listen((duration) {
      if (!mounted || duration == null) {
        return;
      }
      setState(() {
        _playbackDuration = duration;
      });
    });
  }

  @override
  void dispose() {
    _recordTicker?.cancel();
    _playerStateSub?.cancel();
    _positionSub?.cancel();
    _durationSub?.cancel();
    _peerPresenceSub?.cancel();
    _recorder.dispose();
    _audioPlayer.dispose();
    _msgCtrl.removeListener(_onTextChanged);
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final has = _msgCtrl.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  void _clearPendingAttachment() {
    setState(() {
      _pendingAttachment = null;
      _pendingAttachmentType = null;
      _pendingAttachmentName = null;
    });
  }

  Future<void> _pickImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    setState(() {
      _pendingAttachment = File(picked.path);
      _pendingAttachmentType = 'image';
      _pendingAttachmentName = p.basename(picked.path);
    });
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) return;
      final f = result.files.first;
      final path = f.path;
      if (path == null) {
        _showInfo('Could not read the selected file.');
        return;
      }
      setState(() {
        _pendingAttachment = File(path);
        _pendingAttachmentType = 'file';
        _pendingAttachmentName = f.name;
      });
    } on PlatformException catch (_) {
      try {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.any,
          withData: false,
        );
        if (result == null || result.files.isEmpty) return;
        final f = result.files.first;
        final name = f.name.toLowerCase();
        if (!name.endsWith('.pdf') &&
            !name.endsWith('.doc') &&
            !name.endsWith('.docx')) {
          _showInfo('Please select a PDF or Word document.');
          return;
        }
        final path = f.path;
        if (path == null) {
          _showInfo('Could not read the selected file.');
          return;
        }
        setState(() {
          _pendingAttachment = File(path);
          _pendingAttachmentType = 'file';
          _pendingAttachmentName = f.name;
        });
      } catch (_) {
        _showInfo('Could not open file picker. Please try again.');
      }
    }
  }

  Future<void> _showAttachmentSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderLight,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Attach',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  _AttachOption(
                    icon: Icons.image_rounded,
                    label: 'Image',
                    color: const Color(0xFF6366F1),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _pickImage();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AttachOption(
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'PDF',
                    color: const Color(0xFFEF4444),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _pickDocument();
                    },
                  ),
                  const SizedBox(width: 16),
                  _AttachOption(
                    icon: Icons.description_rounded,
                    label: 'Document',
                    color: const Color(0xFF2563EB),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      _pickDocument();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendPendingAttachment() async {
    final file = _pendingAttachment;
    final type = _pendingAttachmentType;
    if (file == null || type == null) return;
    final replyToId = _replyToMessage?.id;
    final replyToPreview = _buildReplyPreview();
    _clearReply();
    _clearPendingAttachment();
    await context.read<MessageCubit>().sendAttachmentMessage(
          file: file,
          messageType: type,
          replyToId: replyToId,
          replyToPreview: replyToPreview,
        );
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _refreshPeerPresence(String peerId) async {
    if (peerId.trim().isEmpty) return;
    await _peerPresenceSub?.cancel();
    _peerPresenceSub =
        _firestore.watchUserDevicePresence(peerId).listen((summary) {
      if (!mounted) return;
      final lastSeen = summary.lastSeenAt;
      if (summary.isOnline) {
        setState(() {
          _peerActiveRecently = true;
          _peerStatusText = 'Online';
        });
        return;
      }

      if (lastSeen == null) {
        setState(() {
          _peerActiveRecently = false;
          _peerStatusText = 'Offline';
        });
        return;
      }

      setState(() {
        _peerActiveRecently = false;
        _peerStatusText = 'Last seen ${timeago.format(lastSeen)}';
      });
    });
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();

    if (!status.isGranted) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Microphone Access Required'),
          content: Text(
            status.isPermanentlyDenied || status.isRestricted
                ? 'Microphone access has been blocked. Please enable it in your phone\'s app settings to send voice messages.'
                : 'StarTrack needs microphone access to record voice messages. Please grant it in app settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Not Now'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        ),
      );
      return;
    }

    final tempDir = await getTemporaryDirectory();
    final path = p.join(
        tempDir.path, 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a');

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        sampleRate: 44100,
        bitRate: 64000,
      ),
      path: path,
    );

    _recordTicker?.cancel();
    _recordStartedAt = DateTime.now();
    setState(() {
      _isRecording = true;
      _isStoppingRecording = false;
      _recordingLocked = false;
      _willCancelRecording = false;
      _recordDragDy = 0;
      _recordFilePath = path;
      _recordingDuration = Duration.zero;
      _recordWavePhase = 0;
    });

    _recordTicker = Timer.periodic(const Duration(milliseconds: 160), (_) {
      if (!mounted || !_isRecording || _recordStartedAt == null) {
        return;
      }
      setState(() {
        _recordingDuration = DateTime.now().difference(_recordStartedAt!);
        _recordWavePhase += 0.22;
      });
    });
  }

  Future<void> _stopRecordingAndSend({bool cancelled = false}) async {
    if (_isStoppingRecording) {
      return;
    }
    _isStoppingRecording = true;

    _recordTicker?.cancel();
    _recordTicker = null;

    try {
      final stopPath = await _recorder.stop();
      final resolvedPath = stopPath ?? _recordFilePath;

      if (!mounted) {
        return;
      }

      final duration = _recordingDuration;
      setState(() {
        _isRecording = false;
        _recordingLocked = false;
        _willCancelRecording = false;
        _recordDragDy = 0;
        _recordingDuration = Duration.zero;
        _recordStartedAt = null;
        _recordFilePath = null;
      });

      if (resolvedPath == null) {
        if (!cancelled) {
          _showInfo('Could not save recording. Please try again.');
        }
        return;
      }

      final file = File(resolvedPath);
      if (cancelled || duration.inMilliseconds < 500) {
        if (await file.exists()) {
          unawaited(file.delete());
        }
        if (cancelled) {
          _showInfo('Recording cancelled');
        }
        return;
      }

      if (!await file.exists()) {
        _showInfo('Recorded file not found. Please try again.');
        return;
      }

      // ignore: use_build_context_synchronously
      final replyToId = _replyToMessage?.id;
      final replyToPreview = _buildReplyPreview();
      _clearReply();
      // ignore: use_build_context_synchronously
      await context.read<MessageCubit>().sendAudioMessage(
            audioFile: file,
            duration: duration,
            replyToId: replyToId,
            replyToPreview: replyToPreview,
          );

      if (!mounted) {
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollCtrl.hasClients) {
          _scrollCtrl.animateTo(
            _scrollCtrl.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      });
    } finally {
      _isStoppingRecording = false;
    }
  }

  Future<void> _handleRecordPressStart() async {
    if (_isRecording) {
      return;
    }
    await _startRecording();
  }

  void _handleRecordDragUpdate(Offset delta) {
    if (!_isRecording) {
      return;
    }
    if (_recordingLocked) {
      return;
    }
    final shouldLock = delta.dy < -56;
    final nextDragDy = delta.dy.clamp(-96.0, 0.0).toDouble();
    if (shouldLock) {
      HapticFeedback.mediumImpact();
      setState(() {
        _recordingLocked = true;
        _willCancelRecording = false;
        _recordDragDy = -96;
      });
      return;
    }
    final shouldCancel = delta.dx < -56;
    // Haptic when crossing into the cancel zone
    if (shouldCancel && !_willCancelRecording) {
      HapticFeedback.mediumImpact();
    }
    if (_willCancelRecording == shouldCancel && _recordDragDy == nextDragDy) {
      return;
    }
    setState(() {
      _willCancelRecording = shouldCancel;
      _recordDragDy = nextDragDy;
    });
  }

  Future<void> _handleRecordPressEnd() async {
    if (!_isRecording) {
      return;
    }
    if (_recordingLocked) {
      return;
    }
    setState(() => _recordDragDy = 0);
    await _stopRecordingAndSend(cancelled: _willCancelRecording);
  }

  Future<void> _cancelRecording() async {
    if (!_isRecording) return;
    await _stopRecordingAndSend(cancelled: true);
  }

  Future<void> _sendLockedRecording() async {
    if (!_isRecording) return;
    await _stopRecordingAndSend(cancelled: false);
  }

  Future<void> _toggleAudioPlayback(MessageModel message) async {
    final source = _normalizedAudioSource(message.fileUrl);
    if (source == null) {
      return;
    }

    final requestId = ++_audioPlaybackRequestId;
    try {
      final isSameMessage = _activeAudioMessageId == message.id;
      if (isSameMessage && _audioPlayer.playing) {
        await _audioPlayer.pause();
        if (!mounted || requestId != _audioPlaybackRequestId) {
          return;
        }
        setState(() {
          _playingMessageId = null;
        });
        return;
      }

      if (!isSameMessage) {
        await _audioPlayer.stop();
        if (!_isRemotePath(source)) {
          final localFile = File(source);
          if (!await localFile.exists()) {
            _showInfo('Voice note file is missing on this device.');
            return;
          }
          await _audioPlayer.setFilePath(source);
        } else {
          await _audioPlayer.setUrl(source);
        }
        await _audioPlayer.setSpeed(_playbackSpeed);

        if (!mounted || requestId != _audioPlaybackRequestId) {
          return;
        }
        setState(() {
          _activeAudioMessageId = message.id;
          _playbackPosition = Duration.zero;
          _playbackDuration = _audioPlayer.duration ?? Duration.zero;
        });
      } else {
        final value = _audioPlayer.playerState;
        final durationMs = _playbackDuration.inMilliseconds;
        final restartThresholdMs = math.max(0, durationMs - 120);
        final isNearEnd = durationMs > 0 &&
            _playbackPosition.inMilliseconds >= restartThresholdMs;
        if (value.processingState == ProcessingState.completed || isNearEnd) {
          await _audioPlayer.seek(Duration.zero);
          if (!mounted || requestId != _audioPlaybackRequestId) {
            return;
          }
          setState(() {
            _playbackPosition = Duration.zero;
          });
        }
      }

      await _audioPlayer.play();
      if (!mounted || requestId != _audioPlaybackRequestId) {
        return;
      }
      setState(() {
        _playingMessageId = message.id;
      });
    } catch (error) {
      if (!mounted || requestId != _audioPlaybackRequestId) {
        return;
      }
      setState(() {
        if (_activeAudioMessageId == message.id) {
          _activeAudioMessageId = null;
        }
        _playingMessageId = null;
      });
      _showInfo('Could not play this voice note.');
      debugPrint(
          '[ChatDetail] audio playback failed for ${message.id}: $error');
    }
  }

  bool _isRemotePath(String input) {
    return input.startsWith('http://') || input.startsWith('https://');
  }

  String? _normalizedAudioSource(String? input) {
    final raw = input?.trim();
    if (raw == null || raw.isEmpty) return null;
    if (_isRemotePath(raw)) return raw;
    if (!raw.startsWith('file://')) return raw;
    try {
      return Uri.parse(raw).toFilePath(windows: Platform.isWindows);
    } catch (_) {
      return raw;
    }
  }

  void _setReplyTo(MessageModel msg) {
    final uid = context.read<MessageCubit>().currentUserId;
    String senderLabel;
    if (msg.senderId == uid) {
      senderLabel = 'You';
    } else {
      final s = context.read<MessageCubit>().state;
      senderLabel = s is ThreadLoaded ? s.peerName : 'Unknown';
    }
    setState(() {
      _replyToMessage = msg;
      _replyToSenderLabel = senderLabel;
    });
  }

  void _clearReply() {
    setState(() {
      _replyToMessage = null;
      _replyToSenderLabel = null;
    });
  }

  String? _buildReplyPreview() {
    final msg = _replyToMessage;
    if (msg == null) return null;
    final text =
        msg.messageType == 'audio' ? '\u{1F3A4} Voice message' : msg.content;
    return '${_replyToSenderLabel ?? 'Unknown'}: $text';
  }

  Future<void> _cyclePlaybackSpeed() async {
    final speeds = <double>[1.0, 1.25, 1.5, 2.0];
    final currentIndex = speeds.indexWhere((item) => item == _playbackSpeed);
    final next = speeds[(currentIndex + 1) % speeds.length];
    await _audioPlayer.setSpeed(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _playbackSpeed = next;
    });
  }

  Future<void> _confirmDeleteAudio(MessageModel message) async {
    final shouldDelete = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Delete voice message?'),
            content: const Text(
              'This removes the message from this conversation. This action cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style:
                    FilledButton.styleFrom(backgroundColor: AppColors.danger),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!shouldDelete) return;

    if (_activeAudioMessageId == message.id ||
        _playingMessageId == message.id) {
      await _audioPlayer.stop();
      if (mounted) {
        setState(() {
          _playingMessageId = null;
          _activeAudioMessageId = null;
          _playbackPosition = Duration.zero;
          _playbackDuration = Duration.zero;
        });
      }
    }

    final localPath = message.fileUrl;
    if (localPath != null && !_isRemotePath(localPath)) {
      final f = File(localPath);
      if (await f.exists()) {
        unawaited(f.delete());
      }
    }

    if (!mounted) return;
    await context.read<MessageCubit>().deleteMessage(message.id);
    if (!mounted) return;
    _showInfo('Voice message deleted');
  }

  Future<void> _showMessageContextSheet(
      MessageModel message, bool isMine) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderLight,
                borderRadius: BorderRadius.circular(99),
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading:
                  const Icon(Icons.reply_rounded, color: AppColors.primary),
              title: const Text('Reply'),
              onTap: () {
                Navigator.of(ctx).pop();
                _setReplyTo(message);
              },
            ),
            if (isMine && message.messageType == 'audio')
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger),
                title: const Text('Delete voice message',
                    style: TextStyle(color: AppColors.danger)),
                onTap: () {
                  Navigator.of(ctx).pop();
                  _confirmDeleteAudio(message);
                },
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _showPeerProfileSheet({
    required String peerId,
    required String peerName,
    required String? peerPhotoUrl,
    required bool isPeerLecturer,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.borderLight,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(height: 14),
              CircleAvatar(
                radius: 34,
                backgroundColor: AppColors.primaryTint10,
                backgroundImage:
                    peerPhotoUrl != null ? NetworkImage(peerPhotoUrl) : null,
                child: peerPhotoUrl == null
                    ? Text(
                        peerName.isNotEmpty ? peerName[0].toUpperCase() : '?',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Text(
                peerName,
                textAlign: TextAlign.center,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _peerStatusText ?? 'Offline',
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _peerActiveRecently
                      ? AppColors.primary
                      : AppColors.textSecondaryLight,
                ),
              ),
              if (isPeerLecturer) ...[
                const SizedBox(height: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.roleLecturer.withValues(alpha: 0.12),
                    borderRadius:
                        BorderRadius.circular(AppDimensions.radiusFull),
                  ),
                  child: Text(
                    'Lecturer',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: AppColors.roleLecturer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        final portfolioPath = Routes.authorPortfolio
                            .replaceFirst(':userId', peerId);
                        context.push(portfolioPath);
                      },
                      icon: const Icon(Icons.work_outline_rounded),
                      label: const Text('View Portfolio'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        final profilePath =
                            Routes.profile.replaceFirst(':userId', peerId);
                        context.push(profilePath);
                      },
                      icon: const Icon(Icons.person_outline_rounded),
                      label: const Text('View Profile'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showInfo(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  void _showNotImplemented(String featureName) {
    _showInfo('$featureName is not implemented yet.');
  }

  Future<void> _sendMessage() async {
    final text = _msgCtrl.text.trim();
    if (text.isEmpty) {
      return;
    }

    _msgCtrl.clear();
    final replyToId = _replyToMessage?.id;
    final replyToPreview = _buildReplyPreview();
    _clearReply();
    await context.read<MessageCubit>().sendMessage(
          text,
          replyToId: replyToId,
          replyToPreview: replyToPreview,
        );

    if (!mounted) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: isDark
            ? const Color(0xFF0B1222).withValues(alpha: 0.92)
            : const Color(0xFFF8FBFF).withValues(alpha: 0.92),
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.primary),
          onPressed: () => context.pop(),
        ),
        title: BlocBuilder<MessageCubit, MessageState>(
          builder: (context, state) {
            if (state is ThreadLoaded) {
              if (_lastLoadedPeerId != state.peerId) {
                _lastLoadedPeerId = state.peerId;
                unawaited(_refreshPeerPresence(state.peerId));
              }
              return _ChatHeader(
                peerName: state.peerName,
                peerPhotoUrl: state.peerPhotoUrl,
                isPeerLecturer: state.isPeerLecturer,
                statusText: _peerStatusText ?? 'Offline',
                isActiveRecently: _peerActiveRecently,
                onTap: () => _showPeerProfileSheet(
                  peerId: state.peerId,
                  peerName: state.peerName,
                  peerPhotoUrl: state.peerPhotoUrl,
                  isPeerLecturer: state.isPeerLecturer,
                ),
              );
            }
            return const _ChatHeader(peerName: 'Conversation');
          },
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () => _showNotImplemented('Conversation menu'),
            tooltip: 'More',
          ),
        ],
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
              right: -60,
              child: _GlowBlob(size: 200, color: Color(0x1A2563EB)),
            ),
            const Positioned(
              bottom: -80,
              left: -60,
              child: _GlowBlob(size: 240, color: Color(0x121152D4)),
            ),
            BlocConsumer<MessageCubit, MessageState>(
              listenWhen: (_, current) => current is ThreadLoaded,
              listener: (context, state) async {
                if (state is ThreadLoaded && _scrollCtrl.hasClients) {
                  await Future<void>.delayed(const Duration(milliseconds: 16));
                  if (_scrollCtrl.hasClients) {
                    _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
                  }
                }
              },
              builder: (context, state) {
                if (state is ThreadLoading || state is MessageInitial) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (state is MessageError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        state.message,
                        style: GoogleFonts.plusJakartaSans(
                          color: AppColors.danger,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                if (state is! ThreadLoaded) {
                  return const SizedBox.shrink();
                }

                final currentUserId = context.read<MessageCubit>().currentUserId;
                final messages = state.messages;
                final safeTopPad =
                    MediaQuery.of(context).padding.top + kToolbarHeight + 4;

                return Column(
                  children: [
                    SizedBox(height: safeTopPad),
                    Expanded(
                      child: messages.isEmpty
                          ? Center(
                              child: Text(
                                'Start the conversation.',
                                style: GoogleFonts.plusJakartaSans(
                                  fontSize: 14,
                                  color: AppColors.textSecondaryLight,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8,
                              ),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final message = messages[index];
                                final previous =
                                    index > 0 ? messages[index - 1] : null;
                                final showDate = previous == null ||
                                    !_isSameDay(
                                      previous.createdAt,
                                      message.createdAt,
                                    );

                                return Column(
                                  children: [
                                    if (showDate)
                                      _DateDivider(
                                        label: _formatDateDivider(
                                          message.createdAt,
                                        ),
                                      ),
                                    _SwipeToReplyBubble(
                                      onReply: () => _setReplyTo(message),
                                      child: GestureDetector(
                                        onLongPress: () =>
                                            _showMessageContextSheet(
                                          message,
                                          message.senderId == currentUserId,
                                        ),
                                        child: _MessageBubble(
                                          message: message,
                                          isMine:
                                              message.senderId == currentUserId,
                                          isAudioPlaying:
                                              _playingMessageId == message.id &&
                                                  _audioPlayer.playing,
                                          playbackPosition:
                                              _activeAudioMessageId ==
                                                      message.id
                                                  ? _playbackPosition
                                                  : Duration.zero,
                                          playbackDuration:
                                              _activeAudioMessageId ==
                                                      message.id
                                                  ? _playbackDuration
                                                  : Duration.zero,
                                          playbackSpeed: _playbackSpeed,
                                          onAudioTap:
                                              message.messageType == 'audio'
                                                  ? () => _toggleAudioPlayback(
                                                        message,
                                                      )
                                                  : null,
                                          onSpeedTap:
                                              message.messageType == 'audio'
                                                  ? _cyclePlaybackSpeed
                                                  : null,
                                          onOpenFile:
                                              (message.messageType == 'file' ||
                                                      message.messageType ==
                                                          'image')
                                                  ? () => _openAttachment(
                                                        message,
                                                      )
                                                  : null,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                    ),
                    _InputBar(
                      controller: _msgCtrl,
                      hasText: _hasText,
                      onSend: _sendMessage,
                      onAttachTap: _showAttachmentSheet,
                      onRecordStart: _handleRecordPressStart,
                      onRecordDrag: _handleRecordDragUpdate,
                      onRecordEnd: _handleRecordPressEnd,
                      onRecordingCancel: _cancelRecording,
                      onRecordingSendLocked: _sendLockedRecording,
                      isRecording: _isRecording,
                      isRecordingLocked: _recordingLocked,
                      willCancelRecording: _willCancelRecording,
                      recordDragDy: _recordDragDy,
                      recordWavePhase: _recordWavePhase,
                      recordingDuration: _recordingDuration,
                      replyToPreviewText: _buildReplyPreview(),
                      onClearReply: _clearReply,
                      pendingAttachmentName: _pendingAttachmentName,
                      pendingAttachmentType: _pendingAttachmentType,
                      onClearAttachment: _clearPendingAttachment,
                      onSendAttachment: _sendPendingAttachment,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment(MessageModel message) async {
    final path = _normalizedAudioSource(message.fileUrl);
    if (path == null) {
      _showInfo('Attachment not available.');
      return;
    }
    if (_isRemotePath(path)) {
      _showInfo('Opening remote attachments is not yet supported.');
      return;
    }
    final file = File(path);
    if (!await file.exists()) {
      _showInfo('File not found on this device.');
      return;
    }
    await OpenFilex.open(path);
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _formatDateDivider(DateTime date) {
    final now = DateTime.now();
    if (_isSameDay(date, now)) {
      return 'Today';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    if (_isSameDay(date, yesterday)) {
      return 'Yesterday';
    }

    return DateFormat('EEE, d MMM').format(date);
  }
}

class _ChatHeader extends StatelessWidget {
  final String peerName;
  final String? peerPhotoUrl;
  final bool isPeerLecturer;
  final String statusText;
  final bool isActiveRecently;
  final VoidCallback? onTap;

  const _ChatHeader({
    required this.peerName,
    this.peerPhotoUrl,
    this.isPeerLecturer = false,
    this.statusText = 'Offline',
    this.isActiveRecently = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
        child: Row(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: AppColors.primaryTint10,
                  backgroundImage:
                      peerPhotoUrl != null ? NetworkImage(peerPhotoUrl!) : null,
                  child: peerPhotoUrl == null
                      ? Text(
                          peerName.isNotEmpty
                              ? peerName[0].toUpperCase()
                              : '?',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        )
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: isActiveRecently
                          ? AppColors.success
                          : AppColors.textSecondaryLight,
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          peerName,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color:
                                Theme.of(context).appBarTheme.foregroundColor,
                          ),
                        ),
                      ),
                      if (isPeerLecturer) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color:
                                AppColors.roleLecturer.withValues(alpha: 0.12),
                            borderRadius:
                                BorderRadius.circular(AppDimensions.radiusFull),
                          ),
                          child: Text(
                            'Lecturer',
                            style: GoogleFonts.plusJakartaSans(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: AppColors.roleLecturer,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    statusText,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isActiveRecently
                          ? AppColors.primary
                          : AppColors.textSecondaryLight,
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
}

class _DateDivider extends StatelessWidget {
  final String label;

  const _DateDivider({required this.label});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.primaryTint10,
            borderRadius: BorderRadius.circular(AppDimensions.radiusFull),
          ),
          child: Text(
            label.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: AppColors.primary,
              letterSpacing: 0.1,
            ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMine;
  final bool isAudioPlaying;
  final Duration playbackPosition;
  final Duration playbackDuration;
  final double playbackSpeed;
  final VoidCallback? onAudioTap;
  final Future<void> Function()? onSpeedTap;
  final VoidCallback? onOpenFile;

  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.isAudioPlaying = false,
    this.playbackPosition = Duration.zero,
    this.playbackDuration = Duration.zero,
    this.playbackSpeed = 1.0,
    this.onAudioTap,
    this.onSpeedTap,
    this.onOpenFile,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timeLabel = DateFormat('hh:mm a').format(message.createdAt);
    final isAudio = message.messageType == 'audio';
    final isImage = message.messageType == 'image';
    final isFile = message.messageType == 'file';
    final bubbleText = message.content;

    final normalizedDuration = playbackDuration.inMilliseconds <= 0
        ? const Duration(seconds: 1)
        : playbackDuration;
    final progress = isAudio
        ? (playbackPosition.inMilliseconds / normalizedDuration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    Widget bubbleChild;
    if (isAudio) {
      bubbleChild = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: onAudioTap,
                borderRadius: BorderRadius.circular(16),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.16)
                            : AppColors.primary.withValues(alpha: 0.12),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAudioPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: isMine ? Colors.white : AppColors.primary,
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _AudioWaveform(
                        progress: isAudioPlaying ? progress : 0,
                        activeColor: isMine ? Colors.white : AppColors.primary,
                        inactiveColor: isMine
                            ? Colors.white.withValues(alpha: 0.28)
                            : AppColors.primary.withValues(alpha: 0.18),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    _formatDuration(
                      isAudioPlaying ? playbackPosition : playbackDuration,
                    ),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: isMine
                          ? Colors.white70
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: () {
                      onSpeedTap?.call();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: isMine
                            ? Colors.white.withValues(alpha: 0.18)
                            : AppColors.primaryTint10,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${playbackSpeed.toStringAsFixed(playbackSpeed.truncateToDouble() == playbackSpeed ? 0 : 2)}x',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: isMine ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
    } else if (isImage) {
      final src = message.fileUrl;
      bubbleChild = GestureDetector(
        onTap: onOpenFile,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: src != null && (src.startsWith('http://') || src.startsWith('https://'))
              ? Image.network(src,
                  width: 200,
                  height: 200,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded))
              : src != null
                  ? Image.file(File(src),
                      width: 200,
                      height: 200,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_rounded))
                  : const SizedBox.shrink(),
        ),
      );
    } else if (isFile) {
      final fname = message.fileName ?? message.content;
      bubbleChild = GestureDetector(
        onTap: onOpenFile,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isMine
                    ? Colors.white.withValues(alpha: 0.18)
                    : const Color(0xFFEF4444).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.picture_as_pdf_rounded,
                color: isMine ? Colors.white : const Color(0xFFEF4444),
                size: 22,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    fname,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isMine ? Colors.white : null,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    'Tap to open',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      color: isMine
                          ? Colors.white70
                          : AppColors.textSecondaryLight,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    } else {
      bubbleChild = Text(
        bubbleText,
        style: GoogleFonts.plusJakartaSans(
          fontSize: 14,
          color: isMine ? Colors.white : null,
          height: 1.5,
        ),
      );
    }

    // Reply quote widget
    Widget? replyQuote;
    if (message.replyToPreview != null && message.replyToPreview!.isNotEmpty) {
      final parts = message.replyToPreview!.split(': ');
      final senderName = parts.length > 1 ? parts.first : 'Reply';
      final previewBody =
          parts.length > 1 ? parts.sublist(1).join(': ') : parts.first;
      replyQuote = Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isMine
              ? Colors.white.withValues(alpha: 0.18)
              : AppColors.primaryTint10,
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMine ? Colors.white : AppColors.primary,
              width: 3,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              senderName,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: isMine ? Colors.white : AppColors.primary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              previewBody,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 12,
                color: isMine ? Colors.white70 : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      );
    }

    final bubbleBody = replyQuote != null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [replyQuote, bubbleChild],
          )
        : bubbleChild;

    if (isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12, left: 48),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.68,
              ),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomLeft: Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: bubbleBody,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  timeLabel,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _statusIcon(),
                  size: 14,
                  color: _statusColor(),
                ),
                const SizedBox(width: 4),
                Text(
                  _statusLabel(),
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 10,
                    color: AppColors.textSecondaryLight,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12, right: 48),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const CircleAvatar(
            radius: 16,
            backgroundColor: AppColors.primaryTint10,
            child:
                Icon(Icons.person_rounded, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.65,
                ),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.surfaceDark : Colors.white,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                    bottomRight: Radius.circular(16),
                  ),
                  boxShadow: isDark
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                ),
                child: bubbleBody,
              ),
              const SizedBox(height: 4),
              Text(
                timeLabel,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 10,
                  color: AppColors.textSecondaryLight,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _statusIcon() {
    final localOnlyAudio =
        message.messageType == 'audio' && !_isRemotePath(message.fileUrl);
    if (localOnlyAudio) {
      return Icons.schedule_rounded;
    }
    if (message.isRead) {
      return Icons.done_all_rounded;
    }
    return Icons.check_rounded;
  }

  Color _statusColor() {
    final localOnlyAudio =
        message.messageType == 'audio' && !_isRemotePath(message.fileUrl);
    if (localOnlyAudio) {
      return AppColors.textSecondaryLight;
    }
    if (message.isRead) {
      return AppColors.primary;
    }
    return AppColors.textSecondaryLight;
  }

  String _statusLabel() {
    final localOnlyAudio =
        message.messageType == 'audio' && !_isRemotePath(message.fileUrl);
    if (localOnlyAudio) {
      return 'Sending';
    }
    if (message.isRead) {
      return 'Read';
    }
    return 'Sent';
  }

  bool _isRemotePath(String? input) {
    if (input == null || input.trim().isEmpty) {
      return false;
    }
    return input.startsWith('http://') || input.startsWith('https://');
  }

  String _formatDuration(Duration value) {
    if (value.inMilliseconds <= 0) {
      return '00:00';
    }
    final minutes = value.inMinutes.toString().padLeft(2, '0');
    final seconds = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final Future<void> Function() onSend;
  final VoidCallback onAttachTap;
  final Future<void> Function() onRecordStart;
  final void Function(Offset delta) onRecordDrag;
  final Future<void> Function() onRecordEnd;
  final Future<void> Function() onRecordingCancel;
  final Future<void> Function() onRecordingSendLocked;
  final bool isRecording;
  final bool isRecordingLocked;
  final bool willCancelRecording;
  final double recordDragDy;
  final double recordWavePhase;
  final Duration recordingDuration;
  final String? replyToPreviewText;
  final VoidCallback? onClearReply;
  final String? pendingAttachmentName;
  final String? pendingAttachmentType;
  final VoidCallback? onClearAttachment;
  final Future<void> Function()? onSendAttachment;

  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.onSend,
    required this.onAttachTap,
    required this.onRecordStart,
    required this.onRecordDrag,
    required this.onRecordEnd,
    required this.onRecordingCancel,
    required this.onRecordingSendLocked,
    required this.isRecording,
    required this.isRecordingLocked,
    required this.willCancelRecording,
    required this.recordDragDy,
    required this.recordWavePhase,
    required this.recordingDuration,
    this.replyToPreviewText,
    this.onClearReply,
    this.pendingAttachmentName,
    this.pendingAttachmentType,
    this.onClearAttachment,
    this.onSendAttachment,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasPending = pendingAttachmentName != null;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF0D1629).withValues(alpha: 0.97)
            : Colors.white.withValues(alpha: 0.97),
        border: Border(
          top: BorderSide(
            color: isDark ? const Color(0xFF1E2D4A) : const Color(0xFFE5EBF5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Reply bar ────────────────────────────────────────────────
              if (replyToPreviewText != null)
                _ReplyPreviewBar(
                  previewText: replyToPreviewText!,
                  onClear: onClearReply ?? () {},
                ),

              // ── Pending attachment preview (hidden while recording) ──────
              if (hasPending && !isRecording)
                _AttachmentPreviewBar(
                  name: pendingAttachmentName!,
                  type: pendingAttachmentType ?? 'file',
                  onClear: onClearAttachment ?? () {},
                  onSend: onSendAttachment,
                ),

              // ── Locked recording row ──────────────────────────────────────
              if (isRecording && isRecordingLocked)
                _LockedRecordingRow(
                  phase: recordWavePhase,
                  duration: recordingDuration,
                  isDark: isDark,
                  onCancel: onRecordingCancel,
                  onSend: onRecordingSendLocked,
                )
              // ── Compose row / unlocked-recording row ─────────────────────
              // The mic _HoldToTalkButton always stays in the widget tree so
              // its GestureDetector keeps tracking the pointer for
              // swipe-to-lock and swipe-to-cancel during recording.
              else if (!hasPending || isRecording)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Left: cancel zone (recording) or attach button
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      transitionBuilder: (child, anim) =>
                          ScaleTransition(scale: anim, child: child),
                      child: isRecording
                          ? _CancelZone(
                              key: const ValueKey('cancel'),
                              willCancel: willCancelRecording,
                              dragFraction:
                                  (-recordDragDy.clamp(-70.0, 0.0) / 70.0)
                                      .clamp(0.0, 1.0),
                            )
                          : _ComposerIconBtn(
                              key: const ValueKey('attach'),
                              icon: Icons.attach_file_rounded,
                              onTap: onAttachTap,
                            ),
                    ),
                    const SizedBox(width: 8),
                    // Centre: inline recording status or text field
                    Expanded(
                      child: isRecording
                          ? _RecordingStatusStrip(
                              duration: recordingDuration,
                              phase: recordWavePhase,
                              willCancel: willCancelRecording,
                              isDark: isDark,
                            )
                          : Container(
                              constraints: const BoxConstraints(maxHeight: 120),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? const Color(0xFF1A2640)
                                    : const Color(0xFFF2F6FC),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: TextField(
                                controller: controller,
                                maxLines: null,
                                textInputAction: TextInputAction.newline,
                                style: GoogleFonts.plusJakartaSans(fontSize: 14),
                                decoration: InputDecoration(
                                  hintText: 'Message…',
                                  hintStyle: GoogleFonts.plusJakartaSans(
                                    fontSize: 14,
                                    color: AppColors.textSecondaryLight,
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 10),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                    ),
                    const SizedBox(width: 8),
                    // Right: send (text typed) or mic (always during recording)
                    if (!isRecording && hasText)
                      _SendButton(onSend: onSend)
                    else
                      Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          // Lock guide floats above mic while recording
                          if (isRecording)
                            Positioned(
                              bottom: 50,
                              child: _LockGuide(dragDy: recordDragDy),
                            ),
                          _HoldToTalkButton(
                            isRecording: isRecording,
                            willCancel: willCancelRecording,
                            dragDy: isRecording ? recordDragDy : 0,
                            onHintTap: () => _showInfo(
                              context,
                              'Hold to record • Slide ↑ to lock • Slide ← to cancel',
                            ),
                            onLongPressStart: onRecordStart,
                            onLongPressMove: onRecordDrag,
                            onLongPressEnd: onRecordEnd,
                          ),
                        ],
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  static void _showInfo(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }
}

// ── Recording panel (full-width, shown instead of text row) ────────────────

// ── Small icon button for composer toolbar ──────────────────────────────────

class _ComposerIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _ComposerIconBtn({super.key, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: isDark
              ? const Color(0xFF1A2640)
              : const Color(0xFFF2F6FC),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, size: 20, color: AppColors.primary),
      ),
    );
  }
}

// ── Pending attachment preview bar ─────────────────────────────────────────

class _AttachmentPreviewBar extends StatelessWidget {
  final String name;
  final String type;
  final VoidCallback onClear;
  final Future<void> Function()? onSend;

  const _AttachmentPreviewBar({
    required this.name,
    required this.type,
    required this.onClear,
    this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final isImage = type == 'image';
    final iconColor =
        isImage ? const Color(0xFF6366F1) : const Color(0xFFEF4444);
    final icon =
        isImage ? Icons.image_rounded : Icons.picture_as_pdf_rounded;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          // Send attachment
          GestureDetector(
            onTap: () => onSend?.call(),
            child: Container(
              width: 32,
              height: 32,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.send_rounded,
                  color: Colors.white, size: 16),
            ),
          ),
          const SizedBox(width: 6),
          // Dismiss
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondaryLight),
          ),
        ],
      ),
    );
  }
}

// ── Attach option tile in bottom sheet ────────────────────────────────────

class _AttachOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _AttachOption({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 26),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.plusJakartaSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ── GlowBlob (same as inbox) ────────────────────────────────────────────────

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
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            radius: 0.9,
          ),
        ),
      ),
    );
  }
}

class _AudioWaveform extends StatelessWidget {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  const _AudioWaveform({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  static const List<double> _barHeights = [
    8,
    14,
    10,
    18,
    12,
    20,
    9,
    16,
    13,
    19,
    11,
    17,
    8,
    14,
    10,
    18,
    12,
    20,
  ];

  @override
  Widget build(BuildContext context) {
    final activeBars = (_barHeights.length * progress).round();

    return SizedBox(
      height: 26,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(_barHeights.length, (index) {
          final isActive = index < activeBars;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            width: 3,
            height: _barHeights[index],
            decoration: BoxDecoration(
              color: isActive ? activeColor : inactiveColor,
              borderRadius: BorderRadius.circular(999),
            ),
          );
        }),
      ),
    );
  }
}

class _HoldToTalkButton extends StatelessWidget {
  final bool isRecording;
  final bool willCancel;
  final double dragDy;
  final VoidCallback onHintTap;
  final Future<void> Function() onLongPressStart;
  final void Function(Offset delta) onLongPressMove;
  final Future<void> Function() onLongPressEnd;

  const _HoldToTalkButton({
    required this.isRecording,
    required this.willCancel,
    required this.dragDy,
    required this.onHintTap,
    required this.onLongPressStart,
    required this.onLongPressMove,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    final lift = isRecording ? dragDy.clamp(-48.0, 0.0).toDouble() : 0.0;
    return GestureDetector(
      onTap: onHintTap,
      onLongPressStart: (_) {
        onLongPressStart();
      },
      onLongPressMoveUpdate: (details) {
        onLongPressMove(details.offsetFromOrigin);
      },
      onLongPressEnd: (_) {
        onLongPressEnd();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        transform: Matrix4.translationValues(0, lift, 0),
        transformAlignment: Alignment.center,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: willCancel
                ? AppColors.danger
                : (isRecording
                    ? AppColors.primary
                    : AppColors.textSecondaryLight.withValues(alpha: 0.16)),
            boxShadow: isRecording
                ? [
                    BoxShadow(
                      color: (willCancel ? AppColors.danger : AppColors.primary)
                          .withValues(alpha: 0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : const [],
          ),
          child: Icon(
            isRecording ? Icons.mic_rounded : Icons.mic_none_rounded,
            color: isRecording ? Colors.white : AppColors.textSecondaryLight,
            size: 20,
          ),
        ),
      ),
    );
  }
}

// ── Cancel zone — shown on the left side during unlocked recording ──────────

class _CancelZone extends StatelessWidget {
  final bool willCancel;
  final double dragFraction; // 0..1 — how far user has slid left

  const _CancelZone({
    super.key,
    required this.willCancel,
    required this.dragFraction,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: willCancel
            ? AppColors.danger
            : AppColors.danger
                .withValues(alpha: 0.06 + 0.14 * dragFraction),
        border: Border.all(
          color: willCancel
              ? AppColors.danger
              : AppColors.danger
                  .withValues(alpha: 0.20 + 0.60 * dragFraction),
          width: 1.5,
        ),
      ),
      child: Icon(
        Icons.delete_outline_rounded,
        size: 18,
        color: willCancel
            ? Colors.white
            : AppColors.danger
                .withValues(alpha: 0.30 + 0.70 * dragFraction),
      ),
    );
  }
}

// ── Inline recording status strip (replaces text field while recording) ──────

class _RecordingStatusStrip extends StatelessWidget {
  final Duration duration;
  final double phase;
  final bool willCancel;
  final bool isDark;

  const _RecordingStatusStrip({
    required this.duration,
    required this.phase,
    required this.willCancel,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = willCancel ? AppColors.danger : AppColors.primary;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A2640) : const Color(0xFFF2F6FC),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: accentColor.withValues(alpha: willCancel ? 0.55 : 0.22),
        ),
      ),
      child: Row(
        children: [
          _PulsingDot(color: accentColor),
          const SizedBox(width: 8),
          Text(
            _fmt(duration),
            style: GoogleFonts.plusJakartaSans(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: accentColor,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: _RecordWave(phase: phase, isDanger: willCancel)),
          const SizedBox(width: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 150),
            child: willCancel
                ? Text(
                    key: const ValueKey('release'),
                    'Release',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger,
                    ),
                  )
                : Row(
                    key: const ValueKey('hint'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.chevron_left_rounded,
                        size: 14,
                        color: AppColors.textSecondaryLight,
                      ),
                      Text(
                        'Cancel',
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 10,
                          color: AppColors.textSecondaryLight,
                        ),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ── Pulsing recording dot ───────────────────────────────────────────────────

class _PulsingDot extends StatelessWidget {
  final Color color;
  const _PulsingDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.45),
            blurRadius: 5,
            spreadRadius: 1,
          ),
        ],
      ),
    );
  }
}

// ── Locked recording row — shown when user swipes up to lock ─────────────────

class _LockedRecordingRow extends StatelessWidget {
  final double phase;
  final Duration duration;
  final bool isDark;
  final Future<void> Function() onCancel;
  final Future<void> Function() onSend;

  const _LockedRecordingRow({
    required this.phase,
    required this.duration,
    required this.isDark,
    required this.onCancel,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.primary.withValues(alpha: 0.12),
              border: Border.all(color: AppColors.primary, width: 1.5),
            ),
            child: const Icon(
              Icons.lock_rounded,
              size: 15,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1A2640)
                    : const Color(0xFFF2F6FC),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const _PulsingDot(color: AppColors.primary),
                  const SizedBox(width: 8),
                  Text(
                    _fmt(duration),
                    style: GoogleFonts.plusJakartaSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: _RecordWave(phase: phase)),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          _RecordingActionChip(
            label: 'Cancel',
            icon: Icons.close_rounded,
            color: AppColors.danger,
            onTap: onCancel,
            outlined: true,
          ),
          const SizedBox(width: 6),
          _RecordingActionChip(
            label: 'Send',
            icon: Icons.send_rounded,
            color: AppColors.primary,
            onTap: onSend,
          ),
        ],
      ),
    );
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

class _LockGuide extends StatelessWidget {
  final double dragDy;

  const _LockGuide({required this.dragDy});

  @override
  Widget build(BuildContext context) {
    final progress = ((dragDy.abs() - 4) / 52).clamp(0.0, 1.0).toDouble();
    final isLocked = progress > 0.95;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 80),
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isLocked
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.08 + 0.22 * progress),
            border: Border.all(
              color: AppColors.primary
                  .withValues(alpha: 0.25 + 0.75 * progress),
              width: 1.5,
            ),
          ),
          child: Icon(
            isLocked ? Icons.lock_rounded : Icons.lock_open_rounded,
            size: 13,
            color: isLocked
                ? Colors.white
                : AppColors.primary
                    .withValues(alpha: 0.35 + 0.65 * progress),
          ),
        ),
        const SizedBox(height: 3),
        // Progress track — fills upward as user slides up
        SizedBox(
          width: 2,
          height: 24,
          child: Stack(
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                width: 2,
                height: 24,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: AppColors.borderLight,
                ),
              ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 60),
                width: 2,
                height: (24 * progress).clamp(0.0, 24.0),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: AppColors.primary
                      .withValues(alpha: 0.5 + 0.5 * progress),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const Icon(
          Icons.keyboard_arrow_up_rounded,
          size: 12,
          color: AppColors.textSecondaryLight,
        ),
      ],
    );
  }
}

class _RecordWave extends StatelessWidget {
  final double phase;
  final bool isDanger;

  const _RecordWave({required this.phase, this.isDanger = false});

  @override
  Widget build(BuildContext context) {
    final color = isDanger ? AppColors.danger : AppColors.primary;
    return Row(
      children: List.generate(8, (index) {
        final value = 0.3 + (0.7 * (math.sin(phase + index * 0.45).abs()));
        final height = 6 + value * 10;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: 3,
            height: height,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(99),
            ),
          ),
        );
      }),
    );
  }
}

class _RecordingActionChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final Future<void> Function() onTap;
  final bool outlined;

  const _RecordingActionChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: () => unawaited(onTap()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: outlined ? Colors.transparent : color,
          borderRadius: BorderRadius.circular(999),
          border: outlined ? Border.all(color: color) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: outlined ? color : Colors.white),
            const SizedBox(width: 4),
            Text(
              label,
              style: GoogleFonts.plusJakartaSans(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: outlined ? color : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SendButton extends StatefulWidget {
  final Future<void> Function() onSend;

  const _SendButton({required this.onSend});

  @override
  State<_SendButton> createState() => _SendButtonState();
}

class _SendButtonState extends State<_SendButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween(begin: 1.0, end: 0.88).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeIn),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) async {
        _ctrl.reverse();
        await widget.onSend();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: AppColors.primary,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}

class _SwipeToReplyBubble extends StatefulWidget {
  final Widget child;
  final VoidCallback onReply;

  const _SwipeToReplyBubble({required this.child, required this.onReply});

  @override
  State<_SwipeToReplyBubble> createState() => _SwipeToReplyBubbleState();
}

class _SwipeToReplyBubbleState extends State<_SwipeToReplyBubble>
    with SingleTickerProviderStateMixin {
  static const double _threshold = 56.0;
  static const double _maxDrag = 72.0;

  double _dragX = 0;
  bool _triggered = false;
  late final AnimationController _snapCtrl;
  double _snapStartX = 0;

  @override
  void initState() {
    super.initState();
    _snapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _snapCtrl.addListener(() {
      setState(() {
        _dragX =
            _snapStartX * (1.0 - Curves.easeOut.transform(_snapCtrl.value));
      });
    });
    _snapCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() {
          _dragX = 0;
          _triggered = false;
        });
        _snapCtrl.reset();
      }
    });
  }

  @override
  void dispose() {
    _snapCtrl.dispose();
    super.dispose();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (details.delta.dx <= 0 && _dragX <= 0) return;
    setState(() {
      _dragX = (_dragX + details.delta.dx).clamp(0, _maxDrag);
    });
    if (!_triggered && _dragX >= _threshold) {
      _triggered = true;
      HapticFeedback.mediumImpact();
      widget.onReply();
    }
  }

  void _onEnd(DragEndDetails _) {
    _snapStartX = _dragX;
    _snapCtrl.forward();
  }

  @override
  Widget build(BuildContext context) {
    final progress = (_dragX / _threshold).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragUpdate: _onUpdate,
      onHorizontalDragEnd: _onEnd,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Transform.translate(
            offset: Offset(_dragX, 0),
            child: widget.child,
          ),
          if (_dragX > 0)
            Positioned(
              left: 4,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: progress,
                  child: Transform.scale(
                    scale: 0.6 + 0.4 * progress,
                    child: const Icon(
                      Icons.reply_rounded,
                      size: 22,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ReplyPreviewBar extends StatelessWidget {
  final String previewText;
  final VoidCallback onClear;

  const _ReplyPreviewBar({required this.previewText, required this.onClear});

  @override
  Widget build(BuildContext context) {
    final parts = previewText.split(': ');
    final senderName = parts.length > 1 ? parts.first : 'Reply';
    final body = parts.length > 1 ? parts.sublist(1).join(': ') : parts.first;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.primaryTint10,
        borderRadius: BorderRadius.circular(10),
        border: const Border(
          left: BorderSide(color: AppColors.primary, width: 3),
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.reply_rounded, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderName,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
                Text(
                  body,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.plusJakartaSans(
                    fontSize: 12,
                    color: AppColors.textSecondaryLight,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onClear,
            child: const Icon(Icons.close_rounded,
                size: 18, color: AppColors.textSecondaryLight),
          ),
        ],
      ),
    );
  }
}
