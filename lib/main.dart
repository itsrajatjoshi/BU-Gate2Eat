import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/config/app_environment.dart';
import 'core/constants/app_constants.dart';
import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'core/widgets/offline_indicator_wrapper.dart';
import 'firebase_options.dart';
import 'services/local_storage_service.dart';
import 'services/notification_router_bridge.dart';
import 'services/notification_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // In release mode, discard debug logs to eliminate CPU and string serialization overhead
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Bound Flutter decoded image cache in RAM to prevent memory bloat on low-end devices
  PaintingBinding.instance.imageCache.maximumSize = 150;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 60 * 1024 * 1024; // 60 MB

  // Lock orientation to portrait (Mobile only)
  if (!kIsWeb) {
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
  }

  // Initialize Firebase and LocalStorage concurrently to overlap disk I/O with native SDK bootstrap
  late final LocalStorageService localStorageService;
  final localStorageFuture = LocalStorageService.create();

  try {
    final results = await Future.wait([
      Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      ),
      localStorageFuture,
    ]);
    final firebaseApp = results[0] as FirebaseApp;
    localStorageService = results[1] as LocalStorageService;
    debugPrint('🔥 Firebase Initialized Successfully! App Name: ${firebaseApp.name}');

    if (!kIsWeb) {
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 100 * 1024 * 1024, // 100 MB bounded disk cache
      );

      // Register top-level background message handler for FCM
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    if (AppEnvironment.useFirebaseEmulator) {
      FirebaseFirestore.instance.useFirestoreEmulator(
        AppEnvironment.emulatorHost,
        AppEnvironment.firestoreEmulatorPort,
      );
      debugPrint('🧪 [Emulator] Connected Firestore to ${AppEnvironment.emulatorHost}:${AppEnvironment.firestoreEmulatorPort}');
    }
  } catch (e, stack) {
    debugPrint('❌ Firebase Initialization Note: $e\n$stack');
    localStorageService = await localStorageFuture;
  }

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

/// Root widget of the BU Gate2Eat application with deep-linking lifecycle integration.
class BUGate2EatApp extends ConsumerStatefulWidget {
  const BUGate2EatApp({super.key});

  @override
  ConsumerState<BUGate2EatApp> createState() => _BUGate2EatAppState();
}

class _BUGate2EatAppState extends ConsumerState<BUGate2EatApp> {
  StreamSubscription<PendingNotification>? _openedAppSubscription;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkColdStartNotification();
      _listenToOpenedAppNotifications();
    });
  }

  void _checkColdStartNotification() {
    final notificationService = ref.read(notificationServiceProvider);
    final localStorage = ref.read(localStorageServiceProvider);
    final pending = notificationService.pendingNotification;
    if (pending != null && mounted) {
      debugPrint('🚀 [App] Processing Cold Start notification: ${pending.orderId}');
      NotificationRouterBridge.handleNotificationTap(
        context: context,
        notification: pending,
        localStorage: localStorage,
        notificationService: notificationService,
        customRouter: appRouter,
      );
    }
  }

  void _listenToOpenedAppNotifications() {
    final notificationService = ref.read(notificationServiceProvider);
    final localStorage = ref.read(localStorageServiceProvider);

    _openedAppSubscription?.cancel();
    _openedAppSubscription =
        notificationService.onNotificationOpened.listen((notification) {
      if (mounted) {
        debugPrint('📱 [App] Background notification tap received: ${notification.orderId}');
        NotificationRouterBridge.handleNotificationTap(
          context: context,
          notification: notification,
          localStorage: localStorage,
          notificationService: notificationService,
          customRouter: appRouter,
        );
      }
    });
  }

  @override
  void dispose() {
    _openedAppSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      themeMode: ThemeMode.light,
      routerConfig: appRouter,
      builder: (context, child) =>
          OfflineIndicatorWrapper(child: child ?? const SizedBox.shrink()),
    );
  }
}
