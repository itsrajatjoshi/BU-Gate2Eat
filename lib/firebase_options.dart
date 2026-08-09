// BU Gate2Eat — Firebase Options for multi-platform support (Android, Web, Desktop)

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
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
