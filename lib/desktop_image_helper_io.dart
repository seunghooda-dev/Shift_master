import 'dart:io';

String? findDesktopImagePathImpl(String baseName, List<String> extensions) {
  final userProfile = Platform.environment['USERPROFILE'];
  if (userProfile == null || userProfile.isEmpty) return null;
  final desktopPath = '$userProfile\\Desktop';

  for (final ext in extensions) {
    final filePath = '$desktopPath\\$baseName$ext';
    if (File(filePath).existsSync()) return filePath;
  }
  return null;
}
