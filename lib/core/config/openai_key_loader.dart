import 'openai_key_loader_stub.dart'
    if (dart.library.io) 'openai_key_loader_io.dart';

Future<String?> loadOpenAiApiKeyFromProjectFile() =>
    loadOpenAiApiKeyFromProjectFileImpl();
