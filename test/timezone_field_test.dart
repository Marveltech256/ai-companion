import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/application/timezone_field.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          (call) async => call.method == 'getLocalTimezone'
              ? 'Africa/Kampala'
              : ['Africa/Kampala', 'Europe/London', 'UTC'],
        ),
  );
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('flutter_timezone'),
          null,
        ),
  );
  testWidgets(
    'device timezone fills automatically, city dropdown supports a manual override',
    (tester) async {
      final c = TextEditingController();
      bool? automatic;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimezoneField(
              controller: c,
              onAutomaticChanged: (v) => automatic = v,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.text, 'Africa/Kampala');
      expect(automatic, true);
      await tester.enterText(find.byType(TextFormField), 'London');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Europe/London').last);
      await tester.pumpAndSettle();
      expect(c.text, 'Europe/London');
      expect(automatic, false);
      await tester.tap(find.text('Use device time zone'));
      await tester.pumpAndSettle();
      expect(c.text, 'Africa/Kampala');
      expect(automatic, true);
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
  testWidgets(
    'an existing manual timezone is preserved until automatic is chosen',
    (tester) async {
      final c = TextEditingController(text: 'Europe/London');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TimezoneField(controller: c, automatic: false)),
        ),
      );
      await tester.pumpAndSettle();
      expect(c.text, 'Europe/London');
      await tester.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
