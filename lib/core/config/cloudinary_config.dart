class CloudinaryConfig {
  CloudinaryConfig._();

  // Safe to ship in a client app. Set these once and release builds work
  // without --dart-define. Keep API secrets out of the app binary.
  static const String cloudName = 'dsdsjjayt';
  static const String uploadPreset = 'startrack_upload';
  static const String assetFolder = 'startrack';

  static bool get isConfigured =>
      cloudName.isNotEmpty && uploadPreset.isNotEmpty;
}