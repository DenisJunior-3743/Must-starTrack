// lib/core/utils/video_cache_utils.dart
//
// Shared video caching helpers – used by both the inline feed player
// (_VideoPageState in home_feed_screen.dart) and the full-screen
// OfflineVideoPlayerScreen.

import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'media_path_utils.dart';

final Map<String, Future<File>> _inFlightVideoDownloads =
  <String, Future<File>>{};

/// Returns a Cloudinary-optimised playback URL (H.264/AAC, 720 p) when
/// [source] is a raw Cloudinary upload URL; otherwise returns [source] unchanged.
String getPreferredPlaybackSource(String source) {
  final candidates = getPlaybackSourceCandidates(source);
  return candidates.isEmpty ? source : candidates.first;
}

/// Returns playback URLs ordered from preferred to most compatible.
///
/// For Cloudinary uploads, we provide multiple H.264 variants so devices with
/// strict decoder limits can still play video.
List<String> getPlaybackSourceCandidates(String source) {
  if (isLocalMediaPath(source)) return <String>[source];

  final uri = Uri.tryParse(source);
  if (uri == null || !uri.host.contains('res.cloudinary.com')) {
    return <String>[source];
  }

  const marker = '/video/upload/';
  final url = uri.toString();
  if (!url.contains(marker)) return <String>[source];

  final afterUpload = url.substring(url.indexOf(marker) + marker.length);
  if (!afterUpload.startsWith('v')) return <String>[source];

  final preferred = url.replaceFirst(
    marker,
    '/video/upload/f_mp4,vc_h264,ac_aac,w_720,c_limit,fps_30,q_auto:good/',
  );

  final compatibility = url.replaceFirst(
    marker,
    '/video/upload/f_mp4,vc_h264:baseline,ac_aac,w_480,c_limit,fps_24,br_700k,q_auto:low/',
  );

  final ultraLow = url.replaceFirst(
    marker,
    '/video/upload/f_mp4,vc_h264:baseline,ac_aac,w_360,c_limit,fps_20,br_420k,q_auto:low/',
  );

  final tiny = url.replaceFirst(
    marker,
    '/video/upload/f_mp4,vc_h264:baseline,ac_aac,w_240,c_limit,fps_15,br_260k,q_auto:low/',
  );

  final candidates = <String>{preferred, compatibility, ultraLow, tiny, source}.toList();
  debugPrint('[VideoCache] playback candidates: $candidates');
  return candidates;
}

/// Returns the deterministic cache [File] path for [source].
/// Returns the local file directly when [source] is already a local path.
Future<File?> getCachedVideoFile(String source) async {
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
  final ext =
      p.extension(uri.path).isNotEmpty ? p.extension(uri.path) : '.mp4';
  return File(p.join(cacheDir.path, '${videoCacheHash(source)}$ext'));
}

/// Downloads [source] to the local cache (or returns the existing cached file).
/// Pass [onProgress] to receive `(receivedBytes, totalBytes)` callbacks.
Future<File> resolveVideoFile(
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

  final cacheFile = await getCachedVideoFile(source);
  if (cacheFile == null) {
    throw Exception('Could not prepare local video cache path.');
  }

  if (!forceRefresh &&
      await cacheFile.exists() &&
      await cacheFile.length() > 1024) {
    debugPrint('[VideoCache] serving from cache: ${cacheFile.path}');
    return cacheFile;
  }

  if (!forceRefresh) {
    final existing = _inFlightVideoDownloads[source];
    if (existing != null) {
      return existing;
    }
  }

  final future = () async {
    final tempFile = File('${cacheFile.path}.part');
    if (await tempFile.exists()) await tempFile.delete();

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

    if (!await tempFile.exists()) {
      throw Exception('Video download temp file missing before commit.');
    }

    final contentType = response.headers.value(Headers.contentTypeHeader);
    final tempLength = await tempFile.length();
    debugPrint(
      '[VideoCache] downloaded: ct=$contentType size=$tempLength path=${tempFile.path}',
    );

    if (tempLength <= 1024) {
      await tempFile.delete().catchError((_) => tempFile);
      throw Exception(
        'Downloaded file too small to be a valid video. '
        'contentType=$contentType size=$tempLength',
      );
    }

    if (await cacheFile.exists()) await cacheFile.delete();
    final finalFile = await tempFile.rename(cacheFile.path);
    debugPrint('[VideoCache] cache committed: ${finalFile.path}');
    return finalFile;
  }();

  _inFlightVideoDownloads[source] = future;
  try {
    return await future;
  } finally {
    _inFlightVideoDownloads.remove(source);
  }
}

/// Deterministic non-cryptographic hash of [input] – used for cache filenames.
String videoCacheHash(String input) {
  var hash = 0;
  for (final codeUnit in input.codeUnits) {
    hash = ((hash * 31) + codeUnit) & 0x7fffffff;
  }
  return hash.toRadixString(16);
}
