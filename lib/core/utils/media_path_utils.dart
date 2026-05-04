bool isVideoMediaPath(String path) {
  final lower = path.toLowerCase();
  // Only explicit video file extensions are reliable.
  // Cloudinary uses /video/upload/ for ALL media (images AND videos),
  // so the path alone cannot be used to identify videos.
  return lower.endsWith('.mp4') ||
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