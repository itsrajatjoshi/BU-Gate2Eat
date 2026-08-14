// BU Gate2Eat — Splash Screen
// Plays the finalized YummBU splash video full-screen, then transitions
// smoothly into the app with a crossfade (avoids harsh light→dark flash).

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

/// The splash background color — exact color sampled from the video asset (#F3F1E4).
/// Ensures zero visible border/rectangle between the video and surrounding screen.
const _splashBgColor = Color(0xFFF3F1E4);

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late VideoPlayerController _videoController;
  bool _videoInitialized = false;
  bool _navigating = false;

  // Crossfade overlay for smooth splash → app transition
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();

    // Make status bar transparent over the splash video
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),);

    // Fade controller for the crossfade transition (600ms)
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );

    _initializeVideo();
  }

  Future<void> _initializeVideo() async {
    _videoController =
        VideoPlayerController.asset('assets/videos/splash.mp4');

    try {
      await _videoController.initialize();
      if (!mounted) return;
      setState(() => _videoInitialized = true);

      // On Android / mobile: full volume (1.0). On web: muted (0.0) to comply with browser autoplay restrictions.
      if (kIsWeb) {
        await _videoController.setVolume(0.0);
      } else {
        await _videoController.setVolume(1.0);
      }

      // Listen for video completion
      _videoController.addListener(_onVideoUpdate);

      // Start playback
      await _videoController.play();

      // Fallback safety timeout in case platform driver doesn't notify completion
      final maxDuration = _videoController.value.duration > Duration.zero
          ? _videoController.value.duration + const Duration(milliseconds: 500)
          : const Duration(seconds: 4);
      Future<void>.delayed(maxDuration, () {
        if (mounted && !_navigating) {
          _navigateAway();
        }
      });
    } catch (e) {
      debugPrint('Splash video initialization error: $e');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      if (mounted) _navigateAway();
    }
  }

  void _onVideoUpdate() {
    if (_navigating) return;

    final value = _videoController.value;
    if (value.isInitialized &&
        value.duration > Duration.zero &&
        value.position >= value.duration - const Duration(milliseconds: 100)) {
      // Video reached completion — trigger smooth transition to app
      _navigateAway();
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

    // Start the fade-out animation (splash fades out)
    await _fadeController.forward();

    if (!mounted) return;

    // Restore system UI style before navigating
    final isDark = Theme.of(context).brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      systemNavigationBarColor: isDark
          ? const Color(0xFF18181B) // AppColors.darkSurface
          : const Color(0xFFFFFFFF), // AppColors.surface
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ),);

    // Navigate to home or onboarding
    final localStorage = ref.read(localStorageServiceProvider);
    if (localStorage.isOnboarded) {
      context.go(AppRoutes.home);
    } else {
      context.go(AppRoutes.onboarding);
    }
  }

  @override
  void dispose() {
    _videoController.removeListener(_onVideoUpdate);
    _videoController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    // Responsive width: 50-55% of screen width (max 280px on tablets/desktop)
    final videoWidth = (screenWidth * 0.52).clamp(160.0, 280.0);

    return Scaffold(
      backgroundColor: _splashBgColor,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Centered small video element (BoxFit.contain, perfectly centered)
          if (_videoInitialized)
            Center(
              child: SizedBox(
                width: videoWidth,
                child: AspectRatio(
                  aspectRatio: _videoController.value.aspectRatio > 0
                      ? _videoController.value.aspectRatio
                      : 1.0,
                  child: VideoPlayer(_videoController),
                ),
              ),
            ),

          // Smooth crossfade overlay into target app theme
          FadeTransition(
            opacity: _fadeAnimation,
            child: Container(
              color: isDark
                  ? const Color(0xFF111113) // AppColors.darkBackground
                  : const Color(0xFFFFF9F5), // AppColors.background
            ),
          ),
        ],
      ),
    );
  }
}
