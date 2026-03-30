import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/media_path_utils.dart';
import '../../../core/utils/video_cache_utils.dart';

class OfflineVideoPlayerScreen extends StatefulWidget {
  final String source;
  final String? title;

  const OfflineVideoPlayerScreen({
    super.key,
    required this.source,
    this.title,
  });

  @override
  State<OfflineVideoPlayerScreen> createState() =>
      _OfflineVideoPlayerScreenState();
}

class _OfflineVideoPlayerScreenState extends State<OfflineVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _loading = true;
  bool _downloading = false;
  bool _savedOffline = false;
  double? _progress;
  String? _error;
  bool _initializedFromNetwork = false;
  String? _debugContext;

  @override
  void initState() {
    super.initState();
    _prepareVideo();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepareVideo({bool forceRefresh = false}) async {
    final playbackSource = getPreferredPlaybackSource(widget.source);
    debugPrint(
      '[OfflineVideo] prepare start: source=${widget.source} '
      'playbackSource=$playbackSource '
      'isLocal=${isLocalMediaPath(widget.source)} forceRefresh=$forceRefresh',
    );
    setState(() {
      _loading = true;
      _downloading = !isLocalMediaPath(widget.source);
      _progress = null;
      _error = null;
      _initializedFromNetwork = false;
      _debugContext = null;
    });

    try {
      await _controller?.dispose();

      final cachedFile = await getCachedVideoFile(playbackSource);
      if (cachedFile != null) {
        final exists = await cachedFile.exists();
        final length = exists ? await cachedFile.length() : 0;
        debugPrint(
          '[OfflineVideo] cache candidate: path=${cachedFile.path} '
          'exists=$exists size=$length',
        );
      }
      final hasUsableCache = !forceRefresh &&
          cachedFile != null &&
          await cachedFile.exists() &&
          await cachedFile.length() > 1024;

      VideoPlayerController controller;
      if (isLocalMediaPath(widget.source)) {
        final localPath = widget.source.startsWith('file://')
            ? Uri.parse(widget.source).toFilePath()
            : widget.source;
        debugPrint('[OfflineVideo] using direct local file: $localPath');
        controller = VideoPlayerController.file(File(localPath));
        await controller.initialize();
        await controller.setLooping(true);
        _savedOffline = true;
      } else if (hasUsableCache) {
        try {
          debugPrint('[OfflineVideo] trying cached file playback: ${cachedFile.path}');
          controller = VideoPlayerController.file(cachedFile);
          await controller.initialize();
          await controller.setLooping(true);
          _savedOffline = true;
        } catch (error, stackTrace) {
          debugPrint('[OfflineVideo] cached playback failed: $error');
          debugPrint('$stackTrace');
          await cachedFile.delete().catchError((_) => cachedFile);
          debugPrint('[OfflineVideo] deleted invalid cache and falling back to network');
          controller = VideoPlayerController.networkUrl(Uri.parse(playbackSource));
          await controller.initialize();
          await controller.setLooping(true);
          _initializedFromNetwork = true;
          unawaited(_downloadForOffline());
        }
      } else {
        debugPrint('[OfflineVideo] no usable cache, streaming from network');
        controller = VideoPlayerController.networkUrl(Uri.parse(playbackSource));
        await controller.initialize();
        await controller.setLooping(true);
        _initializedFromNetwork = true;
        unawaited(_downloadForOffline(forceRefresh: forceRefresh));
      }

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _loading = false;
        _downloading = _initializedFromNetwork;
        _debugContext =
            'mode=${_initializedFromNetwork ? 'network' : 'file'} '
            'saved=$_savedOffline size=${controller.value.size}';
      });
      debugPrint('[OfflineVideo] player ready: ${_debugContext!}');
      await controller.play();
    } catch (error, stackTrace) {
      debugPrint('[OfflineVideo] prepare failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _downloading = false;
        _error = _buildFriendlyVideoError(error);
        _debugContext = 'source=${widget.source} playback=$playbackSource';
      });
    }
  }

  Future<void> _downloadForOffline({bool forceRefresh = false}) async {
    if (isLocalMediaPath(widget.source)) {
      return;
    }

    try {
      final playbackSource = getPreferredPlaybackSource(widget.source);
      final file = await resolveVideoFile(
        playbackSource,
        forceRefresh: forceRefresh,
        onProgress: (received, total) {
          if (!mounted || total <= 0) return;
          setState(() {
            _progress = received / total;
          });
        },
      );

      debugPrint('[OfflineVideo] download complete: path=${file.path}');

      if (!mounted) return;
      final exists = await file.exists();
      final length = exists ? await file.length() : 0;
      debugPrint('[OfflineVideo] cached file stats: exists=$exists size=$length');
      if (exists && length > 1024) {
        setState(() {
          _savedOffline = true;
          _downloading = false;
          _progress = 1;
          _debugContext = 'cachedPath=${file.path} size=$length';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('[OfflineVideo] background download failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _error ??= error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          widget.title ?? 'Video',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.plusJakartaSans(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: _savedOffline ? 'Saved offline' : 'Download for offline use',
            onPressed: _loading ? null : () => _prepareVideo(forceRefresh: false),
            icon: Icon(
              _savedOffline ? Icons.download_done_rounded : Icons.download_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: _error != null
              ? _VideoErrorView(
                  message: _error!,
                  debugContext: _debugContext,
                  onRetry: () => _prepareVideo(forceRefresh: true),
                )
              : controller == null || !controller.value.isInitialized
                  ? _VideoLoadingView(
                      progress: _progress,
                      downloading: _downloading,
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AspectRatio(
                          aspectRatio: controller.value.aspectRatio,
                          child: VideoPlayer(controller),
                        ),
                        const SizedBox(height: 16),
                        VideoProgressIndicator(
                          controller,
                          allowScrubbing: true,
                          colors: const VideoProgressColors(
                            playedColor: AppColors.primary,
                            bufferedColor: Colors.white38,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              onPressed: () {
                                final target = controller.value.position -
                                    const Duration(seconds: 10);
                                controller.seekTo(
                                  target.isNegative ? Duration.zero : target,
                                );
                              },
                              icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                            ),
                            const SizedBox(width: 8),
                            FloatingActionButton(
                              backgroundColor: AppColors.primary,
                              onPressed: () {
                                if (controller.value.isPlaying) {
                                  controller.pause();
                                } else {
                                  controller.play();
                                }
                                setState(() {});
                              },
                              child: Icon(
                                controller.value.isPlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded,
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              onPressed: () {
                                final max = controller.value.duration;
                                final target = controller.value.position +
                                    const Duration(seconds: 10);
                                controller.seekTo(target > max ? max : target);
                              },
                              icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          _savedOffline
                              ? 'Saved offline for later playback'
                              : _initializedFromNetwork
                                  ? 'Streaming now, saving offline in background'
                                  : 'Downloading video...',
                          style: GoogleFonts.plusJakartaSans(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                        if (_debugContext != null) ...[
                          const SizedBox(height: 6),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Text(
                              _debugContext!,
                              style: GoogleFonts.plusJakartaSans(
                                color: Colors.white54,
                                fontSize: 10,
                              ),
                              textAlign: TextAlign.center,
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

String _buildFriendlyVideoError(Object error) {
  final message = error.toString();
  if (_isCodecCapabilityError(message)) {
    return 'This video format is not supported by this device. '
        'The app requested a compatible Cloudinary MP4 variant, but playback still failed. '
        'The uploaded video likely needs server-side transcoding to H.264/AAC SDR before delivery.';
  }

  return message;
}

bool _isCodecCapabilityError(String message) {
  final lower = message.toLowerCase();
  return lower.contains('video/hevc') ||
      lower.contains('hvc1') ||
      lower.contains('no_exceeds_capabilities') ||
      lower.contains('mediacodecvideorenderer error') ||
      lower.contains('codecexception');
}

class _VideoLoadingView extends StatelessWidget {
  final double? progress;
  final bool downloading;

  const _VideoLoadingView({
    required this.progress,
    required this.downloading,
  });

  @override
  Widget build(BuildContext context) {
    final percent = progress == null
        ? null
        : (progress! * 100).clamp(0, 100).round();
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const CircularProgressIndicator(color: AppColors.primary),
        const SizedBox(height: 16),
        Text(
          downloading
              ? percent == null
                  ? 'Downloading video...'
                  : 'Downloading video... $percent%'
              : 'Preparing video...',
          style: GoogleFonts.plusJakartaSans(color: Colors.white),
        ),
      ],
    );
  }
}

class _VideoErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  final String? debugContext;

  const _VideoErrorView({
    required this.message,
    required this.onRetry, this.debugContext,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.white, size: 56),
          const SizedBox(height: 16),
          Text(
            'Video could not be opened',
            style: GoogleFonts.plusJakartaSans(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: GoogleFonts.plusJakartaSans(color: Colors.white70, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          if (debugContext != null) ...[
            const SizedBox(height: 8),
            Text(
              debugContext!,
              style: GoogleFonts.plusJakartaSans(color: Colors.white54, fontSize: 10),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}


