// BU Gate2Eat — Core Providers
// Global Riverpod providers for services and shared state

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import '../services/firestore_service.dart';
import '../services/local_storage_service.dart';
import '../services/force_update_service.dart';

/// Provider for the Firestore service (singleton).
final firestoreServiceProvider = Provider<FirestoreService>((ref) {
  return FirestoreService();
});

/// Provider for the LocalStorage service.
/// Must be overridden in main.dart after initialization.
final localStorageServiceProvider = Provider<LocalStorageService>((ref) {
  throw UnimplementedError('LocalStorageService must be overridden at startup');
});

/// Provider for the ForceUpdate service.
final forceUpdateServiceProvider = Provider<ForceUpdateService>((ref) {
  return ForceUpdateService(ref.read(firestoreServiceProvider));
});

/// Provider for the current theme mode.
/// Reads initial value from local storage, can be updated from Settings.
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  final localStorage = ref.read(localStorageServiceProvider);
  return ThemeModeNotifier(localStorage);
});

/// Manages the app's theme mode state.
class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  final LocalStorageService _localStorage;

  ThemeModeNotifier(this._localStorage) : super(_parseThemeMode(_localStorage.themeMode));

  /// Updates the theme mode and persists the choice.
  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _localStorage.setThemeMode(_themeModeToString(mode));
  }

  static ThemeMode _parseThemeMode(String mode) {
    switch (mode) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'light';
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.system:
        return 'system';
    }
  }
}
