abstract final class OpenAiConfig {
  // Read from --dart-define=OPENAI_API_KEY to avoid committing secrets.
  static const String bundledApiKey =
      String.fromEnvironment('OPENAI_API_KEY', defaultValue: '');

  // Model used for both JSON assistant fallback and recommendation rerank.
  static const String model = 'gpt-4o-mini';
}
