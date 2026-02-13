import 'desktop_image_helper_stub.dart' if (dart.library.io) 'desktop_image_helper_io.dart';

String? findDesktopImagePath(String baseName, List<String> extensions) {
  return findDesktopImagePathImpl(baseName, extensions);
}
