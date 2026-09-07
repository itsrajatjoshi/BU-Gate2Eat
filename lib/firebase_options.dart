// BU Gate2Eat — Firebase Options for multi-platform support (Android, Web, Desktop)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

import 'core/config/app_environment.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    // ── STRICT FAIL-CLOSED ENVIRONMENT SAFETY GATE ──
    // Prevent non-production environments (DEV / STAGING) from silently connecting to live Production.
    if (AppEnvironment.isDev && !AppEnvironment.useFirebaseEmulator) {
      throw UnsupportedError(
        'SECURITY SAFETY BLOCK: APP_ENV is set to "dev", but cloud project "bu-gate2eat-dev" is not provisioned. '
        'To develop safely without touching live production, run with local emulators: '
        'flutter run --dart-define=APP_ENV=dev --dart-define=USE_FIREBASE_EMULATOR=true',
      );
    }
    if (AppEnvironment.isStaging && !AppEnvironment.useFirebaseEmulator) {
      throw UnsupportedError(
        'SECURITY SAFETY BLOCK: APP_ENV is set to "staging", but cloud project "bu-gate2eat-staging" is not provisioned. '
        'Run with emulators or provision the cloud staging project before running staging builds.',
      );
    }

    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyC0M9efTmOQFzHFxiva7NZcwPuTHJJuB8c',
    appId: '1:657799719042:web:0a58db10f7be5f05156c9b',
    messagingSenderId: '657799719042',
    projectId: 'bu-gate2eat',
    authDomain: 'bu-gate2eat.firebaseapp.com',
    storageBucket: 'bu-gate2eat.firebasestorage.app',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyC0M9efTmOQFzHFxiva7NZcwPuTHJJuB8c',
    appId: '1:657799719042:android:0a58db10f7be5f05156c9b',
    messagingSenderId: '657799719042',
    projectId: 'bu-gate2eat',
    storageBucket: 'bu-gate2eat.firebasestorage.app',
  );
}
