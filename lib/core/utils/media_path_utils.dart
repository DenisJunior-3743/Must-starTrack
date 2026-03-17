bool isVideoMediaPath(String path) {
  final lower = path.toLowerCase();
  return lower.contains('/video/upload/') ||
      lower.endsWith('.mp4') ||
      lower.endsWith('.mov') ||
      lower.endsWith('.m4v') ||
      lower.endsWith('.3gp') ||
      lower.endsWith('.webm') ||
      lower.endsWith('.mkv');
}

bool isLocalMediaPath(String path) {
  if (path.isEmpty) {
    return false;
  }

  final lower = path.toLowerCase();
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    return false;
  }

  return lower.startsWith('file://') ||
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(path) ||
      path.startsWith('/') ||
      path.startsWith('\\');
}