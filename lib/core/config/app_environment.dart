// BU Gate2Eat — Security Architecture
// Environment Configuration & Target Definition

/// Supported deployment environments for the YummBU platform.
enum Environment {
  /// Local developer workstation and unit/widget test runs.
  dev,

  /// Automated security rule emulator testing and staging integration verification.
  staging,

  /// Official production environment (Bennett University live campus).
  prod,
}

/// Central environment coordinator for client execution.
///
/// Mandates:
/// 1. Defaults safely to `Environment.prod` when no build flag is provided.
/// 2. Enables local emulator connection via `--dart-define=USE_FIREBASE_EMULATOR=true`.
/// 3. Prevents development/test seed operations from targeting production.
class AppEnvironment {
  AppEnvironment._();

  static const String _rawEnv = String.fromEnvironment('APP_ENV', defaultValue: 'prod');

  /// The active execution environment.
  static Environment get current {
    switch (_rawEnv.trim().toLowerCase()) {
      case 'dev':
      case 'development':
        return Environment.dev;
      case 'staging':
      case 'test':
        return Environment.staging;
      case 'prod':
      case 'production':
      default:
        return Environment.prod;
    }
  }

  /// Whether running in the local development environment.
  static bool get isDev => current == Environment.dev;

  /// Whether running in the staging/security test environment.
  static bool get isStaging => current == Environment.staging;

  /// Whether running in the production live environment.
  static bool get isProd => current == Environment.prod;

  /// Whether client operations should target local Firebase Emulators.
  /// Activated via: `--dart-define=USE_FIREBASE_EMULATOR=true`
  static const bool useFirebaseEmulator =
      bool.fromEnvironment('USE_FIREBASE_EMULATOR', defaultValue: false);

  /// Host address for local Firebase Emulators (default: 'localhost' or '10.0.2.2' for Android emulator).
  static const String emulatorHost =
      String.fromEnvironment('EMULATOR_HOST', defaultValue: 'localhost');

  /// Port assignments matching firebase.json emulator suite.
  static const int authEmulatorPort = 9099;
  static const int firestoreEmulatorPort = 8080;
  static const int storageEmulatorPort = 9199;
  static const int functionsEmulatorPort = 5001;

  /// Human-readable label for logs and diagnostics.
  static String get name => current.name.toUpperCase();
}
