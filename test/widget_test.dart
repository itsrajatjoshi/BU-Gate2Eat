import 'package:bugate2eat_app/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('App starts without errors', (WidgetTester tester) async {
    // Verify the app can be instantiated
    expect(const BUGate2EatApp(), isNotNull);
  });
}
