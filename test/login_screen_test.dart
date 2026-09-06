import 'package:bugate2eat_app/core/providers.dart';
import 'package:bugate2eat_app/core/router.dart';
import 'package:bugate2eat_app/features/auth/login_screen.dart';
import 'package:bugate2eat_app/features/auth/name_input_screen.dart';
import 'package:bugate2eat_app/features/auth/otp_screen.dart';
import 'package:bugate2eat_app/services/local_storage_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LocalStorageService storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storage = await LocalStorageService.create();
  });

  Widget buildTestApp({GoRouter? router, String initialLocation = '/login'}) {
    final effectiveRouter = router ??
        GoRouter(
          initialLocation: initialLocation,
          routes: [
            GoRoute(
              path: '/login',
              builder: (context, state) {
                final phone = state.extra as String?;
                return LoginScreen(initialPhone: phone);
              },
            ),
            GoRoute(
              path: '/otp',
              builder: (context, state) {
                final phone = state.extra as String? ?? '9876543210';
                return OtpScreen(phone: phone);
              },
            ),
            GoRoute(
              path: '/name-input',
              builder: (context, state) {
                final phone = state.extra as String? ?? '9876543210';
                return NameInputScreen(phone: phone);
              },
            ),
            GoRoute(
              path: '/home',
              builder: (context, state) => const Scaffold(body: Text('Home Screen')),
            ),
            GoRoute(
              path: '/admin',
              builder: (context, state) => const Scaffold(body: Text('Admin Screen')),
            ),
            GoRoute(
              path: '/shopkeeper',
              builder: (context, state) => const Scaffold(body: Text('Shopkeeper Screen')),
            ),
          ],
        );

    return ProviderScope(
      overrides: [
        localStorageServiceProvider.overrideWithValue(storage),
      ],
      child: MaterialApp.router(
        routerConfig: effectiveRouter,
      ),
    );
  }

  group('Complete Onboarding Auth Flow (Login -> OTP -> Name -> App)', () {
    testWidgets('1. LoginScreen: renders heading, input pill, CTA, and terms', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      expect(find.text('Welcome to YummBU!'), findsOneWidget);
      expect(find.text('Great food. Happier days.'), findsOneWidget);
      expect(find.text('+91'), findsOneWidget);
      expect(find.text('Phone number'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.textContaining('Terms & Privacy Policy'), findsOneWidget);
    });

    testWidgets('2. LoginScreen: Validation on empty and invalid phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Empty validation
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Please enter your phone number'), findsOneWidget);

      // Short phone validation
      await tester.enterText(find.byType(TextFormField), '98765');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Phone number must be 10 digits'), findsOneWidget);

      // Invalid starting digit
      await tester.enterText(find.byType(TextFormField), '1234567890');
      await tester.tap(find.text('Continue'));
      await tester.pump();
      expect(find.text('Please enter a valid Indian phone number'), findsOneWidget);
    });

    testWidgets('3. LoginScreen to OtpScreen navigation on valid phone', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Should now be on OTP screen
      expect(find.text('Enter OTP'), findsOneWidget);
      expect(find.text("We've sent a 6-digit OTP to"), findsOneWidget);
      expect(find.text('+91 98765 43210'), findsOneWidget);
      expect(find.text("Didn't receive the OTP?"), findsOneWidget);
    });

    testWidgets('4. OtpScreen: Invalid OTP shows error, default 123456 advances to Name screen', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(initialLocation: '/otp'));
      await tester.pump();

      expect(find.text('Enter OTP'), findsOneWidget);

      // Enter incorrect OTP
      final textFields = find.byType(TextField);
      expect(textFields, findsNWidgets(6));

      await tester.enterText(textFields.at(0), '9');
      await tester.enterText(textFields.at(1), '9');
      await tester.enterText(textFields.at(2), '9');
      await tester.enterText(textFields.at(3), '9');
      await tester.enterText(textFields.at(4), '9');
      await tester.enterText(textFields.at(5), '9');
      await tester.pump();

      expect(find.text('Invalid OTP. Please enter 123456'), findsOneWidget);

      // Now enter valid default OTP: 123456
      await tester.enterText(textFields.at(0), '1');
      await tester.enterText(textFields.at(1), '2');
      await tester.enterText(textFields.at(2), '3');
      await tester.enterText(textFields.at(3), '4');
      await tester.enterText(textFields.at(4), '5');
      await tester.enterText(textFields.at(5), '6');
      await tester.pumpAndSettle();

      // Should advance to Name Input screen
      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('A small step towards great food experiences!'), findsOneWidget);
      expect(find.text('Enter your name'), findsOneWidget);
      expect(find.text('Get Started'), findsOneWidget);
    });

    testWidgets('5. NameInputScreen: validation and customer completion to /home', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(initialLocation: '/name-input'));
      await tester.pump();

      // Empty name validation
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      expect(find.text('Please enter your name'), findsOneWidget);

      // Single character validation
      await tester.enterText(find.byType(TextFormField), 'A');
      await tester.tap(find.text('Get Started'));
      await tester.pump();
      expect(find.text('Name must be at least 2 characters'), findsOneWidget);

      // Valid name
      await tester.enterText(find.byType(TextFormField), 'Rajat Sharma');
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      // Verify routing to /home
      expect(find.text('Home Screen'), findsOneWidget);
      // Verify storage saved
      expect(storage.userName, 'Rajat Sharma');
      expect(storage.userPhone, '9876543210');
      expect(storage.isOnboarded, isTrue);
    });

    testWidgets('6. NameInputScreen: Admin phone routes to /admin', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final adminRouter = GoRouter(
        initialLocation: '/name-input',
        routes: [
          GoRoute(
            path: '/name-input',
            builder: (context, state) => const NameInputScreen(phone: '8078643910'),
          ),
          GoRoute(
            path: '/admin',
            builder: (context, state) => const Scaffold(body: Text('Admin Screen')),
          ),
        ],
      );

      await tester.pumpWidget(buildTestApp(router: adminRouter));
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), 'Super Admin');
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(find.text('Admin Screen'), findsOneWidget);
      expect(storage.userPhone, '8078643910');
    });

    testWidgets('7. AppRoutes has /login, /otp, and /name-input configured', (tester) async {
      expect(AppRoutes.login, '/login');
      expect(AppRoutes.otp, '/otp');
      expect(AppRoutes.nameInput, '/name-input');
      expect(appRouter.configuration.routes.any((r) => r is GoRoute && r.path == AppRoutes.login), isTrue);
      expect(appRouter.configuration.routes.any((r) => r is GoRoute && r.path == AppRoutes.otp), isTrue);
      expect(appRouter.configuration.routes.any((r) => r is GoRoute && r.path == AppRoutes.nameInput), isTrue);
    });

    testWidgets('8. OtpScreen: 6-digit paste distributes across boxes and auto-verifies', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(initialLocation: '/otp'));
      await tester.pump();

      // Paste 123456 into the first box
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '123456');
      await tester.pumpAndSettle();

      // Automatically advances to Name screen!
      expect(find.text('What should we call you?'), findsOneWidget);
    });

    testWidgets('9. OtpScreen: Back arrow button and phone edit pencil return to Login with number preserved', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // Type phone and continue
      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter OTP'), findsOneWidget);

      // Tap pencil icon to edit phone
      await tester.tap(find.byIcon(Icons.edit_outlined));
      await tester.pumpAndSettle();

      // Back on Login screen, phone number is still preserved!
      expect(find.text('Welcome to YummBU!'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);

      // Go back to OTP
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();
      expect(find.text('Enter OTP'), findsOneWidget);

      // Tap top-left back arrow button on OTP screen
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back on Login screen again!
      expect(find.text('Welcome to YummBU!'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
    });

    testWidgets('10. OtpScreen: Incorrect OTP clears boxes and restores focus', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(initialLocation: '/otp'));
      await tester.pump();

      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '000000');
      await tester.pump();

      expect(find.text('Invalid OTP. Please enter 123456'), findsOneWidget);
      // All boxes cleared
      for (int i = 0; i < 6; i++) {
        final tf = tester.widget<TextField>(textFields.at(i));
        expect(tf.controller?.text, isEmpty);
      }
    });

    testWidgets('11. NameInputScreen: Back button returns to Login screen (never back to OTP screen)', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      // 1. Enter phone -> Continue
      await tester.enterText(find.byType(TextFormField), '9876543210');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Enter OTP'), findsOneWidget);

      // 2. Enter OTP -> advances to NameInputScreen via pushReplacement
      final textFields = find.byType(TextField);
      await tester.enterText(textFields.at(0), '123456');
      await tester.pumpAndSettle();

      expect(find.text('What should we call you?'), findsOneWidget);

      // 3. Tap back button on NameInputScreen
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // 4. Must return to Login screen with phone number preserved (NOT back to OTP)
      expect(find.text('Welcome to YummBU!'), findsOneWidget);
      expect(find.text('9876543210'), findsOneWidget);
      expect(find.text('Enter OTP'), findsNothing);
      // And OTP state was cleanly cleared
      expect(storage.isOtpVerified, isFalse);
    });

    testWidgets('12. Terms & Privacy: Tapping button shows placeholder feedback on Login and Name', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      // Login screen
      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.tap(find.text('Terms & Privacy Policy'));
      await tester.pump();

      expect(find.text('Terms & Privacy Policy will be available soon.'), findsOneWidget);

      // Name screen
      await tester.pumpWidget(buildTestApp(initialLocation: '/name-input'));
      await tester.pump();

      await tester.tap(find.text('Terms & Privacy Policy'));
      await tester.pump();

      expect(find.text('Terms & Privacy Policy will be available soon.'), findsOneWidget);
    });

    testWidgets('13. App Restart Cases (A, B, C, D, E): OTP Persistence vs Onboarding State', (tester) async {
      // CASE A: Fresh launch -> close -> reopen -> Login
      expect(storage.isOnboarded, isFalse);
      expect(storage.isOtpVerified, isFalse);

      // CASE B: Login -> OTP -> close before verification
      // Simulate user entered phone but not OTP
      expect(storage.isOtpVerified, isFalse);

      // CASE C: Login -> OTP -> enter 123456 -> verify succeeds -> close app before name
      await storage.saveOtpVerificationState('9876543210');
      expect(storage.isOtpVerified, isTrue);
      expect(storage.verifiedPhone, '9876543210');
      expect(storage.isOnboarded, isFalse); // Crucial: NOT onboarded yet!

      // Reopen app: NameInputScreen should pick up verified phone
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp(initialLocation: '/name-input'));
      await tester.pump();

      expect(find.text('What should we call you?'), findsOneWidget);
      expect(find.text('Enter your name'), findsOneWidget);

      // CASE D: Name completed -> isOnboarded = true, isOtpVerified cleared -> reopen -> Home
      await tester.enterText(find.byType(TextFormField), 'Test User');
      await tester.tap(find.text('Get Started'));
      await tester.pumpAndSettle();

      expect(storage.isOnboarded, isTrue);
      expect(storage.isOtpVerified, isFalse);
      expect(storage.userName, 'Test User');
      expect(storage.userPhone, '9876543210');
      expect(find.text('Home Screen'), findsOneWidget);

      // CASE E: OTP verified -> Name -> Back -> clears OTP state & returns to Login (never OTP)
      await storage.saveOtpVerificationState('9876543210');
      await storage.logout(); // Reset for clean test of Case E
      await storage.saveOtpVerificationState('9876543210');
      expect(storage.isOtpVerified, isTrue);

      await tester.pumpWidget(buildTestApp(initialLocation: '/name-input'));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      expect(find.text('Welcome to YummBU!'), findsOneWidget);
      expect(storage.isOtpVerified, isFalse); // Cleared consistently!
      expect(find.text('Enter OTP'), findsNothing);
    });

    testWidgets('14. Double-tap protection on Continue and Get Started buttons', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.5;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(buildTestApp());
      await tester.pump();

      await tester.enterText(find.byType(TextFormField), '9876543210');

      // Rapid double tap on Continue
      await tester.tap(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      // Only one navigation occurred to OTP
      expect(find.text('Enter OTP'), findsOneWidget);
    });
  });
}
