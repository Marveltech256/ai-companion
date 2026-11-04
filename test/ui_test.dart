import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ai_companion/app/morrow_app.dart';
import 'package:ai_companion/design/scene.dart';
import 'package:ai_companion/design/scene_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DesignLibrary library;

  setUpAll(() async {
    for (final family in ['Inter', 'Lora']) {
      final loader = FontLoader(family)
        ..addFont(rootBundle.load('assets/fonts/$family.ttf'));
      await loader.load();
    }
    library = await DesignLibrary.load();
  });

  Future<void> show(WidgetTester tester, String screen, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    await tester.pumpWidget(
      MorrowApp(
        key: ValueKey(screen),
        library: library,
        initialScreen: screen,
        reviewMode: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }

  tearDown(() {
    final binding = TestWidgetsFlutterBinding.instance;
    binding.platformDispatcher.views.first.resetPhysicalSize();
    binding.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  for (final screen in DesignLibrary.screenNames) {
    testWidgets('renders original $screen frame without layout errors', (
      tester,
    ) async {
      final desktop = screen.startsWith('desktop_');
      await show(
        tester,
        screen,
        desktop ? const Size(1440, 1000) : const Size(402, 900),
      );
      expect(find.byType(DesignScene), findsWidgets);
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ImageByteFormat.png);
        final directory = Directory('build/ui-review')
          ..createSync(recursive: true);
        File('${directory.path}/$screen.png')
            .writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    });
  }

  testWidgets('setup, text, memories, voice and return navigation work', (
    tester,
  ) async {
    await show(tester, 'setup', const Size(402, 900));
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DesignButton && widget.label == 'Meet Lumi',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-home')), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DesignButton && widget.label == 'Talk',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-conversation')), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DesignButton && widget.label == 'Memories',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-memories')), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DesignButton && widget.label == 'Home',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is DesignButton && widget.label == 'Or, let’s talk out loud',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-voice')), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is DesignButton && widget.label == 'End',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-conversation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('name and consent stay consistent between screens', (
    tester,
  ) async {
    await show(tester, 'setup', const Size(402, 900));
    await tester.enterText(find.byType(TextField).first, 'Nova');
    await tester.pumpAndSettle();
    expect(
      find.byWidgetPredicate(
        (w) => w is DesignButton && w.label == 'Meet Nova',
      ),
      findsOneWidget,
    );
    final toggle = find.byType(DesignToggle).first;
    expect(tester.widget<DesignToggle>(toggle).value, isTrue);
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(tester.widget<DesignToggle>(toggle).value, isFalse);
    await tester.tap(
      find.byWidgetPredicate(
        (w) => w is DesignButton && w.label == 'Meet Nova',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byWidgetPredicate((w) => w is DesignButton && w.label == 'Memories'),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<DesignToggle>(find.byType(DesignToggle).first).value,
      isFalse,
    );
  });

  testWidgets('desktop switches to supplied mobile layout on narrow viewport', (
    tester,
  ) async {
    await show(tester, 'conversation', const Size(1440, 1000));
    expect(
      find.byKey(const ValueKey('viewport-desktop_conversation')),
      findsOneWidget,
    );
    tester.view.physicalSize = const Size(360, 780);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('viewport-conversation')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop memory search filters the source review records', (
    tester,
  ) async {
    await show(tester, 'desktop_memories', const Size(1440, 1000));
    await tester.enterText(find.byType(TextField), 'Maya');
    await tester.pumpAndSettle();
    expect(find.byType(DesignScene), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
