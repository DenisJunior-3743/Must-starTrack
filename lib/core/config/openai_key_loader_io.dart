import 'dart:io';

Future<String?> loadOpenAiApiKeyFromProjectFileImpl() async {
  final envCandidates = <String>[
    '.env',
    './.env',
    '../.env',
  ];
  for (final path in envCandidates) {
    final envFile = File(path);
    if (!await envFile.exists()) continue;
    final raw = await envFile.readAsString();
    final parsed = _readEnvValue(raw, 'OPENAI_API_KEY');
    if (parsed != null && parsed.isNotEmpty) {
      return parsed;
    }
  }

  final candidates = <String>[
    'Open API.txt',
    './Open API.txt',
    '../Open API.txt',
  ];

  for (final path in candidates) {
    final file = File(path);
    if (!await file.exists()) continue;
    final raw = await file.readAsString();
    final key = raw.trim();
    if (key.isNotEmpty) return key;
  }

  return null;
}

String? _readEnvValue(String envRaw, String key) {
  final lines = envRaw.split(RegExp(r'\r?\n'));
  for (var index = 0; index < lines.length; index += 1) {
    final line = lines[index];
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final separator = trimmed.indexOf('=');
    if (separator <= 0) continue;

    final k = trimmed.substring(0, separator).trim();
    if (k != key) continue;

    var value = trimmed.substring(separator + 1).trim();
    if (value.isEmpty && index + 1 < lines.length) {
      final next = lines[index + 1].trim();
      if (next.isNotEmpty && !next.startsWith('#') && !next.contains('=')) {
        value = next;
      }
    }
    if (value.startsWith('"') && value.endsWith('"') && value.length >= 2) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") &&
        value.endsWith("'") &&
        value.length >= 2) {
      value = value.substring(1, value.length - 1);
    }
    return value.trim();
  }
  return null;
}
