/// Accent-coloured text clears 4.5:1 in light mode (audit U-13).
///
/// Raw green, orange and blue were used as text colours — the codebase's own
/// figures put them at 3.4:1 and 2.3:1 on white — where the `legibleAccent`
/// pass had not reached.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/features/stack/widgets/dca_simulator.dart';
import 'package:sats_stack/features/stack/widgets/stack_goal_card.dart';
import 'package:sats_stack/features/stack/widgets/stack_hero.dart';
import 'package:sats_stack/shared/theme/app_colors.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final (hi, lo) = la > lb ? (la, lb) : (lb, la);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Color colourOf(WidgetTester tester, String text) =>
      tester.widget<Text>(find.textContaining(text)).style!.color!;

  void legible(Color colour, String what) => expect(
    _contrast(colour, AppColors.lightBackground),
    greaterThanOrEqualTo(4.5),
    reason: what,
  );

  testWidgets("the month's change, up and down", (tester) async {
    await pump(tester, const MonthChange(sats: 21000));
    legible(colourOf(tester, 'sats this month'), 'up');
    await pump(tester, const MonthChange(sats: -21000));
    legible(colourOf(tester, 'sats this month'), 'down');
  });

  testWidgets('a DCA scenario', (tester) async {
    for (final colour in [AppColors.success, AppColors.bitcoinOrange]) {
      await pump(
        tester,
        ScenarioRow(
          label: 'Moderate',
          rate: 0.2,
          color: colour,
          sats: 1500000,
          value: 1200,
          currency: 'USD',
        ),
      );
      legible(colourOf(tester, 'sats'), '$colour');
    }
  });

  testWidgets('the goal percentage', (tester) async {
    for (final total in [100000, 800000]) {
      await pump(
        tester,
        StackGoalCard(
          totalSats: total,
          goalSats: 1000000,
          avgMonthlySats: 50000,
          btcPrice: 80000,
          onEdit: () {},
          currency: 'USD',
        ),
      );
      legible(colourOf(tester, '%'), 'at $total sats');
    }
  });
}
