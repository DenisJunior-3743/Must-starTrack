import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/utils/media_path_utils.dart';

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
    final playbackSource = _getPreferredPlaybackSource(widget.source);
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

      final cachedFile = await _getCachedVideoFile(playbackSource);
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
      final playbackSource = _getPreferredPlaybackSource(widget.source);
      final file = await _resolveVideoFile(
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

String _getPreferredPlaybackSource(String source) {
  if (isLocalMediaPath(source)) {
    return source;
  }

  final uri = Uri.tryParse(source);
  if (uri == null || !uri.host.contains('res.cloudinary.com')) {
    return source;
  }

  const marker = '/video/upload/';
  final url = uri.toString();
  if (!url.contains(marker)) {
    return source;
  }

  final afterUpload = url.substring(url.indexOf(marker) + marker.length);
  if (!afterUpload.startsWith('v')) {
    return source;
  }

  final transformed = url.replaceFirst(
    marker,
    '/video/upload/f_mp4,vc_h264,ac_aac,w_720,c_limit,q_auto/',
  );

  if (transformed != source) {
    debugPrint('[OfflineVideo] using Cloudinary playback transform: $transformed');
  }
  return transformed;
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

Future<File> _resolveVideoFile(
  String source, {
  bool forceRefresh = false,
  ProgressCallback? onProgress,
}) async {
  if (isLocalMediaPath(source)) {
    final localPath = source.startsWith('file://')
        ? Uri.parse(source).toFilePath()
        : source;
    return File(localPath);
  }

  final cacheFile = await _getCachedVideoFile(source);
  if (cacheFile == null) {
    throw Exception('Could not prepare local video cache.');
  }

  debugPrint(
    '[OfflineVideo] resolve file: source=$source cachePath=${cacheFile.path} '
    'forceRefresh=$forceRefresh',
  );

  if (!forceRefresh && await cacheFile.exists() && await cacheFile.length() > 1024) {
    debugPrint('[OfflineVideo] using existing cache without redownload');
    return cacheFile;
  }

  final tempFile = File('${cacheFile.path}.part');
  if (await tempFile.exists()) {
    await tempFile.delete();
  }

  final dio = Dio();
  final response = await dio.download(
    source,
    tempFile.path,
    onReceiveProgress: onProgress,
    options: Options(
      followRedirects: true,
      validateStatus: (status) => status != null && status >= 200 && status < 400,
      responseType: ResponseType.bytes,
    ),
  );

  final contentType = response.headers.value(Headers.contentTypeHeader);
  final contentLength = response.headers.value(Headers.contentLengthHeader);
  debugPrint(
    '[OfflineVideo] download response: status=${response.statusCode} '
    'contentType=$contentType contentLength=$contentLength',
  );

  final tempLength = await tempFile.length();
  debugPrint('[OfflineVideo] temp file size after download: $tempLength');
  if (tempLength <= 1024) {
    throw Exception(
      'Downloaded file is too small to be a valid video. '
      'contentType=$contentType size=$tempLength',
    );
  }

  if (await cacheFile.exists()) {
    await cacheFile.delete();
  }
  final finalFile = await tempFile.rename(cacheFile.path);
  debugPrint('[OfflineVideo] cache committed: ${finalFile.path}');
  return finalFile;
}

Future<File?> _getCachedVideoFile(String source) async {
  if (isLocalMediaPath(source)) {
    final localPath = source.startsWith('file://')
        ? Uri.parse(source).toFilePath()
        : source;
    return File(localPath);
  }

  final directory = await getApplicationDocumentsDirectory();
  final cacheDir = Directory(p.join(directory.path, 'video_cache'));
  if (!await cacheDir.exists()) {
    await cacheDir.create(recursive: true);
  }

  final uri = Uri.parse(source);
  final ext = p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp4';
  return File(p.join(cacheDir.path, '${_stableHash(source)}$ext'));
}

String _stableHash(String input) {
  var hash = 0;
  for (final codeUnit in input.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
