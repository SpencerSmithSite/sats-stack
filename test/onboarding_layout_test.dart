/// The onboarding pages lay out on a small phone, at a large text size, and
/// with the keyboard up.
///
/// The Bitcoin server page once rendered blank on every device (a Spacer in a
/// scroll view throws in layout), and the other text pages were fixed columns
/// that overflowed instead of scrolling.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/features/onboarding/pages/bitcoin_server_page.dart';
import 'package:sats_stack/features/onboarding/pages/ready_page.dart';
import 'package:sats_stack/features/onboarding/pages/welcome_page.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  final controller = TextEditingController();
  tearDownAll(controller.dispose);

  final pages = <String, (Widget, String)>{
    'welcome': (const WelcomePage(), 'Sats Stack'),
    'features': (const FeaturesPage(), 'Fully offline'),
    'ready': (const ReadyPage(), "You're ready."),
    'bitcoin server': (
      BitcoinServerPage(controller: controller),
      'Mempool / Esplora URL',
    ),
  };

  const screens = [
    (size: Size(320, 568), scale: 1.0, keyboard: 0.0),
    (size: Size(375, 667), scale: 1.5, keyboard: 0.0),
    (size: Size(375, 667), scale: 1.0, keyboard: 300.0),
  ];

  for (final MapEntry(key: name, value: (page, landmark)) in pages.entries) {
    for (final s in screens) {
      testWidgets(
        '$name page at ${s.size.width.toInt()}×${s.size.height.toInt()}, '
        'text ×${s.scale}, keyboard ${s.keyboard.toInt()}',
        (tester) async {
          tester.view.physicalSize = s.size;
          tester.view.devicePixelRatio = 1;
          tester.view.viewInsets = FakeViewPadding(bottom: s.keyboard);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.light(),
              home: MediaQuery.withClampedTextScaling(
                minScaleFactor: s.scale,
                maxScaleFactor: s.scale,
                child: Scaffold(body: page),
              ),
            ),
          );
          expect(tester.takeException(), isNull);
          // Scrolls to the last widget if it has to: proves the content is
          // reachable, not just that nothing threw.
          await tester.dragUntilVisible(
            find.text(landmark),
            find.byType(Scrollable).first,
            const Offset(0, 200),
          );
          expect(find.text(landmark), findsOneWidget);
        },
      );
    }
  }
}
