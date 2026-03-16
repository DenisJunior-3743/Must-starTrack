import 'dart:io';

import 'package:dio/dio.dart';

import '../../core/config/cloudinary_config.dart';

class CloudinaryService {
  CloudinaryService({
    required Dio dio,
    String cloudName = CloudinaryConfig.cloudName,
    String uploadPreset = CloudinaryConfig.uploadPreset,
  })  : _dio = dio,
      _cloudName = cloudName.isNotEmpty
        ? cloudName
        : const String.fromEnvironment('CLOUDINARY_CLOUD_NAME'),
      _uploadPreset = uploadPreset.isNotEmpty
        ? uploadPreset
        : const String.fromEnvironment('CLOUDINARY_UPLOAD_PRESET');

  final Dio _dio;
  final String _cloudName;
  final String _uploadPreset;

  bool get isConfigured => _cloudName.isNotEmpty && _uploadPreset.isNotEmpty;

  Future<String> uploadFile(
    File file, {
    String folder = CloudinaryConfig.assetFolder,
    void Function(double progress)? onProgress,
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Cloudinary is not configured. Set values in cloudinary_config.dart or use dart-defines.',
      );
    }

    final filename = file.path.split(Platform.pathSeparator).last;
    final endpoint = 'https://api.cloudinary.com/v1_1/$_cloudName/auto/upload';

    final payload = FormData.fromMap({
      'file': await MultipartFile.fromFile(file.path, filename: filename),
      'upload_preset': _uploadPreset,
      'folder': folder,
    });

    final response = await _dio.post<Map<String, dynamic>>(
      endpoint,
      data: payload,
      onSendProgress: (sent, total) {
        if (total > 0 && onProgress != null) {
          onProgress(sent / total);
        }
      },
      options: Options(
        responseType: ResponseType.json,
        validateStatus: (status) => status != null && status >= 200 && status < 400,
      ),
    );

    final body = response.data ?? const <String, dynamic>{};
    final secureUrl = (body['secure_url'] as String?)?.trim();
    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary upload did not return a secure_url.');
    }
    return secureUrl;
  }
}