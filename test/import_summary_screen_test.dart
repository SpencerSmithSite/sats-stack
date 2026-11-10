/// The screen that says what an import did (audit T-1: no tests at all).
///
/// Pins the counts and how they are worded — rows skipped because the source
/// had them, and rows already in the ledger from another import — the date
/// range, where its two buttons go, and that it fits a small phone at a
/// large text size.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/screens/import/import_summary_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  /// The summary pushed over a starting page, as the import screen does.
  Future<void> show(
    WidgetTester tester,
    ImportSummary summary, {
    Size size = const Size(430, 932),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder:
              (context, _) => Scaffold(
                body: TextButton(
                  onPressed:
                      () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => ImportSummaryScreen(summary: summary),
                        ),
                      ),
                  child: const Text('Import screen'),
                ),
              ),
        ),
        GoRoute(
          path: '/transactions',
          builder: (_, _) => const Scaffold(body: Text('Transactions tab')),
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        builder:
            (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(textScale)),
              child: child!,
            ),
      ),
    );
    await tester.tap(find.text('Import screen'));
    await tester.pumpAndSettle();
  }

  final full = ImportSummary(
    imported: 12,
    duplicatesSkipped: 3,
    alreadyInLedger: 2,
    total: 17,
    sourceName: 'Monzo',
    sourceId: 1,
    startDate: DateTime(2026, 3, 1),
    endDate: DateTime(2026, 3, 31),
  );

  testWidgets('the counts, the source and its date range', (tester) async {
    await show(tester, full);
    expect(find.text('Import Complete'), findsOneWidget);
    expect(find.text('Monzo'), findsOneWidget);
    expect(find.text('Mar 1, 2026 – Mar 31, 2026'), findsOneWidget);
    expect(find.text('12'), findsOneWidget); // imported
    expect(find.text('5'), findsOneWidget); // skipped: 3 + 2
    expect(find.text('17'), findsOneWidget); // found
    expect(
      find.text(
        '2 were already in your transactions from another import, so they '
        'were not added twice.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('one already in the ledger reads in the singular', (
    tester,
  ) async {
    await show(
      tester,
      const ImportSummary(
        imported: 4,
        duplicatesSkipped: 0,
        alreadyInLedger: 1,
        total: 5,
        sourceName: 'Monzo',
        sourceId: 1,
      ),
    );
    expect(
      find.text(
        '1 was already in your transactions from another import, so it was '
        'not added twice.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('with no dates and nothing in the ledger, neither is shown', (
    tester,
  ) async {
    await show(
      tester,
      const ImportSummary(
        imported: 4,
        duplicatesSkipped: 1,
        total: 5,
        sourceName: 'Monzo',
        sourceId: 1,
      ),
    );
    expect(find.textContaining('–'), findsNothing);
    expect(find.textContaining('already in your transactions'), findsNothing);
  });

  testWidgets('View Transactions goes to the tab', (tester) async {
    await show(tester, full);
    await tester.tap(find.text('View Transactions'));
    await tester.pumpAndSettle();
    expect(find.text('Transactions tab'), findsOneWidget);
  });

  testWidgets('Import Another File goes back to the import screen', (
    tester,
  ) async {
    await show(tester, full);
    await tester.tap(find.text('Import Another File'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportSummaryScreen), findsNothing);
    expect(find.text('Import screen'), findsOneWidget);
  });

  testWidgets('on an ordinary phone the buttons sit at the foot', (
    tester,
  ) async {
    await show(tester, full);
    final bottom = tester.getBottomLeft(find.text('Import Another File')).dy;
    expect(bottom, greaterThan(932 - 80));
  });

  testWidgets('fits a small phone at a large text size', (tester) async {
    await show(tester, full, size: const Size(320, 568), textScale: 2);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('Import Another File'), 100);
    expect(find.text('Import Another File'), findsOneWidget);
  });
}
