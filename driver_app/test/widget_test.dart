import 'package:flutter_test/flutter_test.dart';
import 'package:driver_app/main.dart';

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const DriverApp());

    // Verify that our login screen is shown.
    expect(find.text('Sarathi'), findsOneWidget);
  });
}
