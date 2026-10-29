/// Screen-reader labels, touch-target size and large-text layout.
///
/// Before this pass there was no `Semantics` anywhere in the UI layer, the
/// month arrows were 20–22px and the insight refresh 14px, and the
/// transaction row overflowed at large text sizes. These use Flutter's own
/// accessibility guidelines where one exists, so the bar is the platform's,
/// not a number picked here.
library;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/budget_progress.dart';
import 'package:sats_stack/features/budgets/widgets/budget_card.dart';
import 'package:sats_stack/features/dashboard/widgets/hero_card.dart';
import 'package:sats_stack/features/dashboard/widgets/metric_tile.dart';
import 'package:sats_stack/features/stack/widgets/period_chip.dart';
import 'package:sats_stack/features/transactions/widgets/transaction_list_item.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';
import 'package:sats_stack/shared/utils/colour_names.dart';
import 'package:sats_stack/shared/widgets/month_selector.dart';
import 'package:sats_stack/shared/widgets/tappable.dart';

/// Pumps [child] on a real [width]-wide screen at [textScale].
///
/// Sets the test view itself rather than wrapping a `MediaQuery`: an
/// overridden `MediaQuery.size` changes what widgets *read*, not the
/// constraints they are laid out in, so the first version of these tests ran
/// on the default 800px window and passed against the row that overflowed.
Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  double textScale = 1,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearAllTestValues);
  await tester.pumpWidget(
    MaterialApp(theme: AppTheme.light(), home: Scaffold(body: child)),
  );
}

void main() {
  group('Tappable', () {
    testWidgets('is announced as a labelled, selectable button', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Center(
          child: Tappable(
            label: 'Red',
            selected: true,
            onTap: () {},
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(Tappable)),
        matchesSemantics(
          label: 'Red',
          isButton: true,
          isSelected: true,
          hasSelectedState: true,
          isEnabled: true,
          hasEnabledState: true,
          hasTapAction: true,
          // Reachable from the keyboard, which a bare GestureDetector is not.
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('pads a 20px control out to a 48px target', (tester) async {
      await _pump(
        tester,
        Center(
          child: Tappable(
            onTap: () {},
            child: const SizedBox(width: 20, height: 20),
          ),
        ),
      );
      final size = tester.getSize(find.byType(Tappable));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
      // The visible part is unchanged.
      expect(tester.getSize(find.byType(SizedBox).last), const Size(20, 20));
    });

    testWidgets('a row of period chips meets the platform guidelines', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final p in const ['1M', '3M', '1Y', 'All'])
                PeriodChip(label: p, selected: p == '1Y', onTap: () {}),
            ],
          ),
        ),
      );
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });
  });

  group('MonthSelector', () {
    testWidgets('names its arrows and meets the tap-target guideline', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await _pump(
        tester,
        MonthSelector(
          month: DateTime(2026, 3),
          onPrevious: () {},
          onNext: null,
        ),
      );

      expect(find.byTooltip('Previous month'), findsOneWidget);
      expect(find.byTooltip('Next month'), findsOneWidget);
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull, reason: 'no stepping into the future');
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      handle.dispose();
    });

    testWidgets('fits a narrow app bar at double text size', (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: MonthSelector(
                month: DateTime(2026, 9), // "September" — the longest
                onPrevious: () {},
                onNext: () {},
              ),
              actions: [
                IconButton(icon: const Icon(Icons.settings), onPressed: () {}),
              ],
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('large text', () {
    final tx = Transaction(
      id: 1,
      walletId: 1,
      date: DateTime(2026, 3, 4),
      description: 'A merchant with a fairly long name, as they often are',
      amountSats: -123456789,
      amountFiat: -123456.78,
      fiatCurrency: 'USD',
      source: 'manual',
      isBitcoin: false,
      dedupHash: 'h',
      createdAt: DateTime(2026, 3, 4),
    );

    for (final scale in const [1.0, 2.0, 3.0]) {
      testWidgets('a transaction row does not overflow at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          TransactionListItem(transaction: tx, category: null, btcPrice: 80000),
          textScale: scale,
          width: 360,
        );
        // Was a RenderFlex overflow: the amount column would not give way.
        expect(tester.takeException(), isNull);
      });

      testWidgets('a categorised, repeating row does not overflow at '
          '${scale}x', (tester) async {
        await _pump(
          tester,
          TransactionListItem(
            transaction: tx.copyWith(recurringPeriod: const Value('monthly')),
            category: const Category(
              id: 1,
              name: 'Subscriptions and memberships',
              color: '#6AB0E8',
              icon: 'subscriptions',
              isSystem: false,
            ),
            btcPrice: 80000,
          ),
          textScale: scale,
          width: 360,
        );
        // The category line was a Row of unconstrained text.
        expect(tester.takeException(), isNull);
      });

      testWidgets('the hero card does not overflow at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          const SingleChildScrollView(
            child: HeroCard(
              totalStackSats: 123456789,
              monthChangeSats: -2345678,
              btcPrice: 81234.56,
              currency: 'USD',
            ),
          ),
          textScale: scale,
          width: 360,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('a budget card does not overflow at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          SingleChildScrollView(
            child: BudgetCard(
              progress: BudgetProgress(
                budget: Budget(
                  id: 1,
                  categoryId: 1,
                  amountFiat: 12345.67,
                  currency: 'USD',
                  period: 'monthly',
                  createdAt: DateTime(2026),
                ),
                category: const Category(
                  id: 1,
                  name: 'Food & Dining',
                  color: '#E24B4A',
                  icon: 'restaurant',
                  isSystem: true,
                ),
                spentFiat: 9876.54,
                limitFiat: 12345.67,
              ),
              btcPrice: 81234.56,
              currency: 'USD',
              onEdit: () {},
              onDelete: () {},
            ),
          ),
          textScale: scale,
          width: 360,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('the stack goal tile does not overflow at ${scale}x', (
        tester,
      ) async {
        await _pump(
          tester,
          const SingleChildScrollView(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: StackGoalTile(
                    progress: 0.123,
                    currentSats: 12345678,
                    goalSats: 100000000,
                  ),
                ),
                SizedBox(width: 10),
                Expanded(child: SizedBox()),
              ],
            ),
          ),
          textScale: scale,
          width: 360,
        );
        expect(tester.takeException(), isNull);
      });
    }
  });

  test('swatches get distinguishable spoken names', () {
    expect(colourName(const Color(0xFFE24B4A)), 'Red');
    expect(colourName(const Color(0xFF1D9E75)), 'Teal');
    expect(colourName(const Color(0xFFF7931A)), 'Orange');
    expect(colourName(const Color(0xFF378ADD)), 'Blue');
    expect(colourName(const Color(0xFF888780)), 'Grey');
  });

  testWidgets('a Tappable can be pressed from the keyboard', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      Center(
        child: Tappable(
          label: 'Refresh',
          onTap: () => taps++,
          child: const Icon(Icons.refresh, size: 14),
        ),
      ),
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(taps, 1);
  });
}
