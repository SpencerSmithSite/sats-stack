/// Small things the third review found in the UI.
///
/// The splash added ~2.5 s to every cold start and ignored reduced motion.
/// The hero's "Import a Bitcoin wallet" pill looked tappable and was not. The
/// category icon grid's cells were about 33 px. Errors raised inside a sheet
/// showed behind it.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/features/dashboard/widgets/hero_card.dart';
import 'package:sats_stack/features/settings/widgets/categories_sheet.dart';
import 'package:sats_stack/screens/splash_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/widgets/inline_error.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('splash', () {
    Future<bool Function()> pumpSplash(
      WidgetTester tester, {
      bool reduceMotion = false,
    }) async {
      var done = false;
      await tester.pumpWidget(
        MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: SplashScreen(onComplete: () => done = true),
          ),
        ),
      );
      return () => done;
    }

    testWidgets('is over in well under two seconds', (tester) async {
      final done = await pumpSplash(tester);
      // In frames, as it would really run: each step awaits the last.
      for (var t = 0; t < 1500; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    });

    testWidgets('a tap skips it', (tester) async {
      final done = await pumpSplash(tester);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byType(SplashScreen));
      for (var t = 0; t < 300; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
      // Let the abandoned sequence's last timer run out.
      await tester.pump(const Duration(seconds: 2));
    });

    testWidgets('with reduced motion it does not animate the coins', (
      tester,
    ) async {
      final done = await pumpSplash(tester, reduceMotion: true);
      for (var t = 0; t < 400; t += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(done(), isTrue);
    });
  });

  testWidgets('the hero card\'s wallet prompt opens something', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: HeroCard(
            totalStackSats: 0,
            monthChangeSats: 0,
            btcPrice: null,
            currency: 'USD',
            onAddWallet: () => opened = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('Import a Bitcoin wallet to track your stack'));
    expect(opened, isTrue);
  });

  testWidgets('the category icon grid has 48 px targets', (tester) async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: CategoriesSheet(categoryService: CategoryService(db)),
        ),
      ),
    );
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    final add = find.text('Add category', skipOffstage: false);
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();

    final cell = find.bySemanticsLabel('restaurant');
    expect(cell, findsOneWidget);
    final size = tester.getSize(cell);
    expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    await tester.runAsync(db.close);
  });

  testWidgets('an inline error shows its message, and nothing when null', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Column(children: [InlineError(null), InlineError('Nope')]),
        ),
      ),
    );
    expect(find.text('Nope'), findsOneWidget);
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
  });
}
