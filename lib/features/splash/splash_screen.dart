// BU Gate2Eat — Splash Screen
// Plays the full-screen final splash video (H.264 + AAC) edge-to-edge (BoxFit.fill),
// then transitions smoothly into the app with robust lifecycle and audio-focus recovery.

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with WidgetsBindingObserver {
  VideoPlayerController? _videoController;
  bool _videoInitialized = false;
  bool _hasStartedPlaying = false;
  bool _navigating = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Make status bar and navigation bar transparent and edge-to-edge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    // Safety fallback timer (3.5s) to guarantee splash NEVER freezes indefinitely during phone calls
    _safetyTimer = Timer(const Duration(milliseconds: 3500), () {
      if (mounted && !_navigating) {
        _navigateAway();
      }
    });

    _initializeVideo();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_navigating) return;

    if (state == AppLifecycleState.resumed) {
      // If returning to the app from a phone call, incoming call banner, or background:
      final controller = _videoController;
      if (controller != null && _videoInitialized) {
        final value = controller.value;
        if (value.position >= value.duration - const Duration(milliseconds: 300) ||
            value.isCompleted) {
          _navigateAway();
        } else if (!value.isPlaying) {
          controller.play().catchError((_) {});
        }
      } else {
        _navigateAway();
      }
    }
  }

  Future<void> _initializeVideo() async {
    final controller =
        VideoPlayerController.asset('assets/videos/final_splash.mp4');
    _videoController = controller;

    try {
      await controller.initialize();
      if (!mounted) return;

      // On Android / mobile: full volume (1.0). On web: muted (0.0) for browser autoplay compliance.
      if (kIsWeb) {
        await controller.setVolume(0.0);
      } else {
        try {
          await controller.setVolume(1.0);
        } catch (_) {
          // In case audio focus restriction prevents setting volume, continue gracefully
        }
      }
      await controller.setLooping(false);

      // Start playback
      await controller.play();
      if (!mounted) return;

      _hasStartedPlaying = true;
      setState(() => _videoInitialized = true);

      // Listen for video completion
      controller.addListener(_onVideoUpdate);
    } catch (e) {
      debugPrint('Splash video initialization error: $e');
      if (mounted && !_navigating) {
        _navigateAway();
      }
    }
  }

  void _onVideoUpdate() {
    final controller = _videoController;
    if (_navigating || !_hasStartedPlaying || controller == null) return;

    final value = controller.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;

    // Ensure video has actually begun playback past the first 300ms
    if (value.position > const Duration(milliseconds: 300)) {
      final isAtEnd =
          value.position >= value.duration - const Duration(milliseconds: 100);

      if (isAtEnd || value.isCompleted) {
        _navigateAway();
      }
    }
  }

  Future<void> _navigateAway() async {
    if (_navigating || !mounted) return;
    _navigating = true;

    _safetyTimer?.cancel();

    // Check force update with timeout (same as original splash logic)
    try {
      final forceUpdateService = ref.read(forceUpdateServiceProvider);
      final updateResult = await forceUpdateService
          .checkForUpdate()
          .timeout(const Duration(seconds: 1));

      if (!mounted) return;

      if (updateResult.isUpdateRequired) {
        // Force update required — stay on this screen
        return;
      }
    } catch (_) {
      // Ignore network timeout or Firestore offline errors on splash
    }

    if (!mounted) return;

    // Restore system UI style before navigating
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(
      SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: isDark
            ? const Color(0xFF18181B) // AppColors.darkSurface
            : const Color(0xFFFFFFFF), // AppColors.surface
        systemNavigationBarIconBrightness:
            isDark ? Brightness.light : Brightness.dark,
      ),
    );

    // Navigate to home, shopkeeper, admin, or onboarding
    final localStorage = ref.read(localStorageServiceProvider);
    if (localStorage.isOnboarded) {
      final phone = localStorage.userPhone;
      if (AppAuthRoles.isAdminPhone(phone)) {
        context.go(AppRoutes.admin);
      } else if (AppAuthRoles.isShopkeeperPhone(phone)) {
        context.go(AppRoutes.shopkeeper);
      } else {
        context.go(AppRoutes.home);
      }
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _safetyTimer?.cancel();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _videoController;
    return Scaffold(
      backgroundColor: const Color(0xFFF3EEE2),
      body: SizedBox.expand(
        child: (_videoInitialized && controller != null)
            ? FittedBox(
                fit: BoxFit.fitWidth,
                child: SizedBox(
                  width: controller.value.size.width > 0
                      ? controller.value.size.width
                      : 1440,
                  height: controller.value.size.height > 0
                      ? controller.value.size.height
                      : 2560,
                  child: VideoPlayer(controller),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
