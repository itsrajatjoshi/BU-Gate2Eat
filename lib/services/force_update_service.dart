// BU Gate2Eat — Services
// Force update service for checking minimum app version

import 'package:package_info_plus/package_info_plus.dart';

import 'firestore_service.dart';

/// Result of a force update check.
class ForceUpdateResult {
  /// Creates a ForceUpdateResult instance.
  const ForceUpdateResult({
    required this.isUpdateRequired,
    this.message,
    this.playStoreUrl,
    this.appStoreUrl,
  });

  final bool isUpdateRequired;
  final String? message;
  final String? playStoreUrl;
  final String? appStoreUrl;
}

/// Service for checking if the app needs a mandatory update.
class ForceUpdateService {
  /// Creates a ForceUpdateService instance.
  ForceUpdateService(this._firestoreService);

  final FirestoreService _firestoreService;

  /// Checks if the current app version is below the minimum required version.
  /// Returns [ForceUpdateResult] with update info if needed.
  /// Returns non-required result if config is unavailable (e.g., offline).
  Future<ForceUpdateResult> checkForUpdate() async {
    try {
      final config = await _firestoreService.getAppConfig();
      if (config == null) {
        return const ForceUpdateResult(isUpdateRequired: false);
      }

      final minVersion = config['minAppVersion'] as String? ?? '1.0.0';
      final message = config['forceUpdateMessage'] as String? ??
          'Please update the app to continue.';
      final playStoreUrl = config['playStoreUrl'] as String?;
      final appStoreUrl = config['appStoreUrl'] as String?;

      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;

      final isRequired = _isVersionLower(currentVersion, minVersion);

      return ForceUpdateResult(
        isUpdateRequired: isRequired,
        message: message,
        playStoreUrl: playStoreUrl,
        appStoreUrl: appStoreUrl,
      );
    } catch (e) {
      // If we can't check (offline, error), don't block the user
      return const ForceUpdateResult(isUpdateRequired: false);
    }
  }

  /// Compares two semantic version strings (e.g., "1.0.0" < "1.1.0").
  /// Returns true if [current] is lower than [minimum].
  bool _isVersionLower(String current, String minimum) {
    final currentParts = current.split('.').map(int.parse).toList();
    final minimumParts = minimum.split('.').map(int.parse).toList();

    // Pad to 3 parts
    while (currentParts.length < 3) {
      currentParts.add(0);
    }
    while (minimumParts.length < 3) {
      minimumParts.add(0);
    }

    for (int i = 0; i < 3; i++) {
      if (currentParts[i] < minimumParts[i]) return true;
      if (currentParts[i] > minimumParts[i]) return false;
    }

    return false; // versions are equal
  }
}
