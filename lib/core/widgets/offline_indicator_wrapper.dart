// BU Gate2Eat — Core Widgets
// Offline Indicator Wrapper (Checkpoint 3 — Offline / Weak Internet)
// Displays a non-intrusive slim banner when the device loses network connectivity.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../constants/app_constants.dart';
import '../providers.dart';

/// Wraps the application to show a minimal, non-intrusive offline indicator
/// when network connectivity is unavailable.
class OfflineIndicatorWrapper extends ConsumerWidget {
  const OfflineIndicatorWrapper({
    required this.child,
    super.key,
  });

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);

    return Material(
      color: Colors.transparent,
      child: Column(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            height: isOnline ? 0 : 28,
            width: double.infinity,
            color: const Color(0xFF202024),
            child: isOnline
                ? const SizedBox.shrink()
                : const SafeArea(
                    bottom: false,
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_off_rounded,
                            size: 14,
                            color: AppColors.warning,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'No Internet connection',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
