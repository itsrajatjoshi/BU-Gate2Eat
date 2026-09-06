// BU Gate2Eat — OTP Verification Screen
// Clean, modern auth screen with ZERO doodles, 60%+ hero framing, and smooth keyboard scroll-up

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/router.dart';

class OtpScreen extends ConsumerStatefulWidget {
  const OtpScreen({
    required this.phone,
    super.key,
    this.heroImageProvider,
  });

  final String phone;
  final ImageProvider? heroImageProvider;

  @override
  ConsumerState<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends ConsumerState<OtpScreen> {
  static const int _otpLength = 6;
  static const String _defaultOtp = '123456';

  final List<TextEditingController> _controllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _focusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  String? _errorMessage;
  int _resendCountdown = 30;
  Timer? _countdownTimer;
  bool _isVerifying = false;

  @override
  void initState() {
    super.initState();
    _startResendTimer();
    // Auto focus first box after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _focusNodes[0].canRequestFocus) {
        _focusNodes[0].requestFocus();
      }
    });
  }

  void _startResendTimer() {
    _countdownTimer?.cancel();
    setState(() => _resendCountdown = 30);
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCountdown > 1) {
        setState(() => _resendCountdown--);
      } else {
        setState(() => _resendCountdown = 0);
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    for (final c in _controllers) {
      c.dispose();
    }
    for (final f in _focusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  String get _currentOtp =>
      _controllers.map((c) => c.text.trim()).join();

  void _onDigitChanged(int index, String value) {
    setState(() => _errorMessage = null);

    final digits = value.replaceAll(RegExp(r'\D'), '');

    if (digits.length >= _otpLength || (digits.length > 1 && index == 0)) {
      // Handle paste of multiple digits
      for (int i = 0; i < _otpLength; i++) {
        if (i < digits.length) {
          _controllers[i].text = digits[i];
        } else {
          _controllers[i].clear();
        }
      }
      if (digits.length >= _otpLength) {
        _focusNodes[_otpLength - 1].unfocus();
        _verifyOtp();
      } else {
        _focusNodes[digits.length.clamp(0, _otpLength - 1)].requestFocus();
      }
      return;
    }

    if (digits.length > 1) {
      // Replacement character typed into already filled box
      final newChar = digits.substring(digits.length - 1);
      _controllers[index].text = newChar;
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
      if (_currentOtp.length == _otpLength) {
        _verifyOtp();
      }
      return;
    }

    if (digits.isNotEmpty) {
      if (index < _otpLength - 1) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _focusNodes[index].unfocus();
      }
    }

    if (_currentOtp.length == _otpLength) {
      _verifyOtp();
    }
  }

  void _onBackspace(int index) {
    if (index > 0 && _controllers[index].text.isEmpty) {
      _focusNodes[index - 1].requestFocus();
      _controllers[index - 1].clear();
    }
  }

  Future<void> _verifyOtp() async {
    if (_isVerifying) return;
    final entered = _currentOtp;
    if (entered.length < _otpLength) {
      setState(() => _errorMessage = 'Please enter complete 6-digit OTP');
      return;
    }

    if (entered != _defaultOtp) {
      setState(() {
        _errorMessage = 'Invalid OTP. Please enter $_defaultOtp';
      });
      // Clear input and refocus first box
      for (final c in _controllers) {
        c.clear();
      }
      if (mounted && _focusNodes[0].canRequestFocus) {
        _focusNodes[0].requestFocus();
      }
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorMessage = null;
    });

    try {
      // Persist temporary OTP verification state locally (isOtpVerified = true)
      // DO NOT set isOnboarded = true yet!
      await ref.read(localStorageServiceProvider).saveOtpVerificationState(widget.phone);
      if (!mounted) return;
      // Navigate to Name Input screen and replace/clear the OTP route completely
      context.go(AppRoutes.nameInput, extra: widget.phone);
    } finally {
      if (mounted) {
        setState(() => _isVerifying = false);
      }
    }
  }

  void _onResendOtp() {
    if (_resendCountdown > 0) return;
    _startResendTimer();
    setState(() => _errorMessage = null);
    for (final c in _controllers) {
      c.clear();
    }
    if (mounted && _focusNodes[0].canRequestFocus) {
      _focusNodes[0].requestFocus();
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'New OTP sent: $_defaultOtp',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w500),
        ),
        backgroundColor: AppColors.textPrimary,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _navigateBackToLogin() {
    if (context.canPop()) {
      context.pop();
    } else {
      context.go(AppRoutes.login, extra: widget.phone);
    }
  }

  String _formatPhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'\D'), '');
    if (digits.length >= 10) {
      final p1 = digits.substring(0, 5);
      final p2 = digits.substring(5, 10);
      return '+91 $p1 $p2';
    }
    return '+91 $raw';
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

    // Sizing: Hero photo occupies 60%+ when keyboard is closed.
    // When keyboard opens, smoothly slide the card up so input is completely visible.
    final heroHeight = screenHeight * 0.62;
    final defaultCardTop = screenHeight * 0.60;
    final cardTop = isKeyboardOpen ? math.max(50.0, screenHeight * 0.16) : defaultCardTop;

    return PopScope(
      canPop: !isKeyboardOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && isKeyboardOpen) {
          FocusScope.of(context).unfocus();
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
                // ─── 1. TOP HERO FOOD PHOTOGRAPH (60%+ Screen Height) ───
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
                                bottom: isKeyboardOpen ? 12.0 : (math.max(bottomInset, 16.0) + 16.0),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // ─── Title (Simple, Clean & Balanced) ───
                                  Text(
                                    'Enter OTP',
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
                                    "We've sent a 6-digit OTP to",
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.textSecondary,
                                      letterSpacing: -0.1,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),

                                  const SizedBox(height: 4),

                                  // Phone number with edit pencil
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _formatPhone(widget.phone),
                                        style: GoogleFonts.outfit(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _navigateBackToLogin,
                                        child: const Padding(
                                          padding: EdgeInsets.all(6.0),
                                          child: Icon(
                                            Icons.edit_outlined,
                                            size: 16,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 24),

                                  // ─── 6 Individual OTP Boxes (52px Height Target) ───
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: List.generate(_otpLength, (index) {
                                      final hasError = _errorMessage != null;
                                      final isFocused = _focusNodes[index].hasFocus;

                                      return Container(
                                        width: 46,
                                        height: 52,
                                        margin: const EdgeInsets.symmetric(horizontal: 4),
                                        decoration: BoxDecoration(
                                          color: AppColors.surface,
                                          borderRadius: BorderRadius.circular(14),
                                          border: Border.all(
                                            color: hasError
                                                ? AppColors.error
                                                : isFocused
                                                    ? AppColors.primary
                                                    : const Color(0xFFEBE6E0),
                                            width: isFocused ? 2.0 : 1.2,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(alpha: 0.03),
                                              blurRadius: 6,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: KeyboardListener(
                                          focusNode: FocusNode(),
                                          onKeyEvent: (event) {
                                            if (event is KeyDownEvent &&
                                                event.logicalKey ==
                                                    LogicalKeyboardKey.backspace &&
                                                _controllers[index].text.isEmpty) {
                                              _onBackspace(index);
                                            }
                                          },
                                          child: Center(
                                            child: TextField(
                                              controller: _controllers[index],
                                              focusNode: _focusNodes[index],
                                              textAlign: TextAlign.center,
                                              keyboardType: TextInputType.number,
                                              textInputAction: TextInputAction.done,
                                              onSubmitted: (_) => FocusScope.of(context).unfocus(),
                                              style: GoogleFonts.outfit(
                                                fontSize: 22,
                                                fontWeight: FontWeight.w700,
                                                color: AppColors.textPrimary,
                                              ),
                                              inputFormatters: [
                                                FilteringTextInputFormatter.digitsOnly,
                                              ],
                                              decoration: const InputDecoration(
                                                counterText: '',
                                                filled: false,
                                                fillColor: Colors.transparent,
                                                border: InputBorder.none,
                                                focusedBorder: InputBorder.none,
                                                enabledBorder: InputBorder.none,
                                                contentPadding: EdgeInsets.zero,
                                                isDense: true,
                                              ),
                                              onChanged: (val) => _onDigitChanged(index, val),
                                            ),
                                          ),
                                        ),
                                      );
                                    }),
                                  ),

                                  if (_errorMessage != null) ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      _errorMessage!,
                                      style: GoogleFonts.inter(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.error,
                                      ),
                                    ),
                                  ],

                                  const SizedBox(height: 28),

                                  // ─── Resend OTP Section (Balanced Hierarchy) ───
                                  Text(
                                    "Didn't receive the OTP?",
                                    style: GoogleFonts.outfit(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      color: AppColors.textSecondary,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: _resendCountdown == 0 ? _onResendOtp : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      child: Text.rich(
                                        TextSpan(
                                          children: [
                                            TextSpan(
                                              text: _resendCountdown > 0
                                                  ? 'Resend in '
                                                  : 'Resend OTP',
                                              style: GoogleFonts.outfit(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: _resendCountdown > 0
                                                    ? AppColors.textSecondary
                                                    : AppColors.primary,
                                              ),
                                            ),
                                            if (_resendCountdown > 0)
                                              TextSpan(
                                                text: '00:${_resendCountdown.toString().padLeft(2, '0')}',
                                                style: GoogleFonts.outfit(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w700,
                                                  color: AppColors.primary,
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

                          // Top-Left Back Arrow Button (Positioned on top layer of card)
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
