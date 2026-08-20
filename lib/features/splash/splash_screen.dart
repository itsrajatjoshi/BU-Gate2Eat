// BU Gate2Eat — Splash Screen
// Plays the full-screen final splash video (H.264 + AAC) edge-to-edge (BoxFit.fill),
// then transitions smoothly into the app.

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  bool _hasStartedPlaying = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();

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

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _videoController =
        VideoPlayerController.asset('assets/videos/final_splash.mp4');

    try {
      await _videoController.initialize();
      if (!mounted) return;

      // On Android / mobile: full volume (1.0). On web: muted (0.0) for browser autoplay compliance.
      if (kIsWeb) {
        await _videoController.setVolume(0.0);
      } else {
        await _videoController.setVolume(1.0);
      }
      await _videoController.setLooping(false);

      // Start playback
      await _videoController.play();
      if (!mounted) return;

      _hasStartedPlaying = true;
      setState(() => _videoInitialized = true);

      // Listen for video completion
      _videoController.addListener(_onVideoUpdate);
    } catch (e) {
      debugPrint('Splash video initialization error: $e');
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) _navigateAway();
    }
  }

  void _onVideoUpdate() {
    if (_navigating || !_hasStartedPlaying) return;

    final value = _videoController.value;
    if (!value.isInitialized || value.duration <= Duration.zero) return;

    // Ensure video has actually begun playback past the first 300ms
    if (value.position > const Duration(milliseconds: 300)) {
      final isAtEnd =
          value.position >= value.duration - const Duration(milliseconds: 100);

      if (isAtEnd) {
        _navigateAway();
      }
    }
  }

  Future<void> _navigateAway() async {
    if (_navigating || !mounted) return;
    _navigating = true;

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

    // Navigate to home, shopkeeper, or onboarding (GoRouter's FadeTransition handles the single smooth fade)
    final localStorage = ref.read(localStorageServiceProvider);
    if (localStorage.isOnboarded) {
      final cleanPhone =
          localStorage.userPhone.replaceAll(RegExp(r'[^0-9]'), '');
      if (cleanPhone.endsWith('8078643910') || cleanPhone == '8078643910') {
        context.go(AppRoutes.admin);
      } else if (cleanPhone.endsWith('8000383993') ||
          cleanPhone == '8000383993') {
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
    _videoController.removeListener(_onVideoUpdate);
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3EEE2),
      body: SizedBox.expand(
        child: _videoInitialized
            ? FittedBox(
                fit: BoxFit.fitWidth,
                child: SizedBox(
                  width: _videoController.value.size.width > 0
                      ? _videoController.value.size.width
                      : 1440,
                  height: _videoController.value.size.height > 0
                      ? _videoController.value.size.height
                      : 2560,
                  child: VideoPlayer(_videoController),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }
}
