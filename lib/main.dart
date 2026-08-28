import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'firebase_options.dart';
import 'services/local_storage_service.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Set system UI overlay style
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: AppColors.surface,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize Firebase
  try {
    final firebaseApp = await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('🔥 Firebase Initialized Successfully! App Name: ${firebaseApp.name}');

    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
      );
    }
  } catch (e, stack) {
    debugPrint('❌ Firebase Initialization Note: $e\n$stack');
  }

  // Initialize local storage
  final localStorageService = await LocalStorageService.create();

  // Initialize Notification Service foundation asynchronously
  final notificationService = NotificationService();
  notificationService.initialize(localStorage: localStorageService).catchError((Object e) {
    debugPrint('⚠️ [FCM] NotificationService init catch: $e');
  });

  runApp(
    ProviderScope(
      overrides: [
        // Override the local storage provider with the initialized instance
        localStorageServiceProvider.overrideWithValue(localStorageService),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const BUGate2EatApp(),
    ),
  );
}

/// Root widget of the BU Gate2Eat application.
class BUGate2EatApp extends ConsumerWidget {
  const BUGate2EatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);

    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: appRouter,
    );
  }
}
