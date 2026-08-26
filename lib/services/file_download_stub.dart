// BU Gate2Eat — File Download Helper (Stub for Native / VM)
import 'dart:typed_data';

/// Stub implementation for non-web platforms.
Future<void> downloadFileToBrowser({
  required Uint8List bytes,
  required String fileName,
  required String mimeType,
}) async {
  // No-op on native platforms (handled via share sheet / file system)
}
