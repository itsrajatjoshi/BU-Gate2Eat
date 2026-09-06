// BU Gate2Eat — Name Input Screen
// Clean, modern auth screen with ZERO doodles, 60%+ hero framing, and smooth keyboard scroll-up

import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';
import '../../models/order_model.dart';
import '../cart/cart_provider.dart';

class NameInputScreen extends ConsumerStatefulWidget {
  const NameInputScreen({
    required this.phone,
    super.key,
    this.heroImageProvider,
  });

  final String phone;
  final ImageProvider? heroImageProvider;

  @override
  ConsumerState<NameInputScreen> createState() => _NameInputScreenState();
}

class _NameInputScreenState extends ConsumerState<NameInputScreen> {
  final _nameController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String get _effectivePhone {
    if (widget.phone.isNotEmpty) return widget.phone;
    return ref.read(localStorageServiceProvider).verifiedPhone;
  }

  Future<void> _navigateBackToLogin() async {
    final phone = _effectivePhone;
    await ref.read(localStorageServiceProvider).clearOtpVerificationState();
    if (!mounted) return;
    context.go(AppRoutes.login, extra: phone);
  }

  void _onTermsTap() {
    // Tappable placeholder action ready for future website/webview redirect
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Terms & Privacy Policy will be available soon.',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.textPrimary,
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _onGetStarted() async {
    if (_isLoading) return;
    setState(() => _errorMessage = null);

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter your name');
      return;
    }
    if (name.length < 2) {
      setState(() => _errorMessage = 'Name must be at least 2 characters');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final localStorage = ref.read(localStorageServiceProvider);
      final phone = _effectivePhone;

      // Save profile with validated name and phone
      // Note: saveUserProfile marks isOnboarded = true and clears temporary OTP verification state!
      await localStorage.saveUserProfile(
        name: name,
        phone: phone,
      );

      // Synchronize identity and reset relevant scoped providers
      ref.read(customerIdentityProvider.notifier).refresh();
      ref.read(cartProvider.notifier).clearCart();
      ref.read(dummyOrdersProvider.notifier).setOrders(<AppOrder>[]);
      ref.invalidate(customerActiveOrdersStreamProvider);
      ref.invalidate(customerOrderHistoryStreamProvider);
      ref.invalidate(favoritesProvider);
      ref.invalidate(currentShopkeeperShopIdProvider);
      ref.invalidate(shopActiveOrdersStreamProvider);
      ref.invalidate(shopOrderHistoryStreamProvider);
      ref.invalidate(shopStatsStreamProvider);
      ref.invalidate(shopCategoriesProvider);
      ref.invalidate(shopMenuItemsProvider);

      // Non-blocking notification permission & token sync
      try {
        final notificationService = ref.read(notificationServiceProvider);
        await notificationService.requestPermission();
        await notificationService.syncCurrentSessionToken(localStorage: localStorage);
      } catch (e) {
        debugPrint('⚠️ [NameInput] Note during notification session sync: $e');
      }

      if (!mounted) return;

      // Role-based routing
      if (AppAuthRoles.isAdminPhone(phone)) {
        context.go(AppRoutes.admin);
      } else if (AppAuthRoles.isShopkeeperPhone(phone)) {
        context.go(AppRoutes.shopkeeper);
      } else {
        context.go(AppRoutes.home);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final size = mediaQuery.size;
    final screenHeight = size.height;
    final screenWidth = size.width;
    final bottomInset = mediaQuery.padding.bottom;
    final keyboardHeight = mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = keyboardHeight > 0;

    // Sizing: Hero photo occupies 60%+ when keyboard is closed (FROZEN).
    // When keyboard opens, smoothly slide the card up so input is completely visible.
    final heroHeight = screenHeight * 0.62;
    final defaultCardTop = screenHeight * 0.60;
    final cardTop = isKeyboardOpen ? math.max(50.0, screenHeight * 0.16) : defaultCardTop;

    return PopScope(
      canPop: !isKeyboardOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (isKeyboardOpen) {
            FocusScope.of(context).unfocus();
          } else {
            _navigateBackToLogin();
          }
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        resizeToAvoidBottomInset: false,
        body: AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            systemNavigationBarColor: AppColors.background,
            systemNavigationBarIconBrightness: Brightness.dark,
          ),
          child: SizedBox(
            width: screenWidth,
            height: screenHeight,
            child: Stack(
              children: [
                // ─── 1. TOP HERO FOOD PHOTOGRAPH (60%+ Screen Height - FROZEN) ───
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: heroHeight,
                  child: Image(
                    image: widget.heroImageProvider ??
                        const AssetImage('assets/images/fries_hero.jpeg'),
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                  ),
                ),

                // ─── 2. STRAIGHT PARTITION BOTTOM SHEET (Smooth Keyboard Slide-Up) ──
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  left: 0,
                  right: 0,
                  top: cardTop,
                  bottom: isKeyboardOpen ? keyboardHeight : 0,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.14),
                          blurRadius: 18,
                          offset: const Offset(0, -4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                      child: Stack(
                        children: [
                          // Card Scrollable Content
                          Positioned.fill(
                            child: SingleChildScrollView(
                              physics: const ClampingScrollPhysics(),
                              padding: EdgeInsets.only(
                                left: 24,
                                right: 24,
                                top: 22,
                                bottom: isKeyboardOpen ? 12.0 : (math.max(bottomInset, 16.0) + 12.0),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // ─── Title (Simple, Clean & Balanced) ───
                                  Text(
                                    'What should we call you?',
                                    style: GoogleFonts.outfit(
                                      fontSize: 26,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.textPrimary,
                                      letterSpacing: -0.4,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 6),

                                  // Subtitle
                                  Text(
                                    'A small step towards great food experiences!',
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.textSecondary,
                                      letterSpacing: -0.1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 22),

                                  // ─── Name Input Pill (52px Balanced Target) ────
                                  Container(
                                    height: 52,
                                    decoration: BoxDecoration(
                                      color: AppColors.surface,
                                      borderRadius: BorderRadius.circular(26),
                                      border: Border.all(
                                        color: _errorMessage != null
                                            ? AppColors.error
                                            : const Color(0xFFEBE6E0),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.03),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 18),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.person_outline_rounded,
                                          size: 20,
                                          color: Color(0xFFA8A099),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: TextFormField(
                                            controller: _nameController,
                                            textCapitalization: TextCapitalization.words,
                                            textInputAction: TextInputAction.done,
                                            style: GoogleFonts.outfit(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w500,
                                              color: AppColors.textPrimary,
                                            ),
                                            decoration: InputDecoration(
                                              hintText: 'Enter your name',
                                              hintStyle: GoogleFonts.outfit(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w400,
                                                color: const Color(0xFFB0A9A2),
                                              ),
                                              filled: false,
                                              fillColor: Colors.transparent,
                                              border: InputBorder.none,
                                              focusedBorder: InputBorder.none,
                                              enabledBorder: InputBorder.none,
                                              errorBorder: InputBorder.none,
                                              disabledBorder: InputBorder.none,
                                              contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                              isDense: true,
                                            ),
                                            onFieldSubmitted: (_) => FocusScope.of(context).unfocus(),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (_errorMessage != null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _errorMessage!,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 16),

                                  // ─── Get Started Button (52px Balanced Height) ───
                                  SizedBox(
                                    width: double.infinity,
                                    height: 52,
                                    child: ElevatedButton(
                                      onPressed: _isLoading ? null : _onGetStarted,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: AppColors.primary,
                                        foregroundColor: Colors.white,
                                        elevation: 2,
                                        shadowColor: AppColors.primary.withValues(alpha: 0.35),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(26),
                                        ),
                                        padding: EdgeInsets.zero,
                                      ),
                                      child: _isLoading
                                          ? const SizedBox(
                                              width: 22,
                                              height: 22,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.2,
                                                color: Colors.white,
                                              ),
                                            )
                                          : Row(
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  'Get Started',
                                                  style: GoogleFonts.outfit(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white,
                                                    letterSpacing: 0.2,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                const Icon(
                                                  Icons.arrow_forward_rounded,
                                                  size: 19,
                                                  color: Colors.white,
                                                ),
                                              ],
                                            ),
                                    ),
                                  ),

                                  const SizedBox(height: 20),

                                  // ─── Terms & Privacy Button/Link ─────
                                  Wrap(
                                    alignment: WrapAlignment.center,
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        'By continuing, you agree to our ',
                                        style: GoogleFonts.inter(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w400,
                                          color: AppColors.textSecondary,
                                        ),
                                      ),
                                      InkWell(
                                        onTap: _onTermsTap,
                                        borderRadius: BorderRadius.circular(4),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 2),
                                          child: Text(
                                            'Terms & Privacy Policy',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.primary,
                                              decoration: TextDecoration.underline,
                                              decorationColor: AppColors.primary,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Top-Left Back Arrow Button (Directs to LoginScreen)
                          Positioned(
                            left: 10,
                            top: 12,
                            child: IconButton(
                              icon: const Icon(
                                Icons.arrow_back,
                                color: AppColors.textPrimary,
                                size: 22,
                              ),
                              splashRadius: 20,
                              onPressed: _navigateBackToLogin,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
