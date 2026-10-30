/// The DCA simulator responds to typing, and ranks its scenarios the right
/// way round.
///
/// It read its amount only when something else rebuilt the screen, so typing
/// changed nothing. And every scenario was valued at today's price, so the
/// one assuming the most growth — which buys the fewest sats — showed the
/// smallest value.
library;

import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/features/stack/widgets/dca_simulator.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  test('the optimistic scenario is worth the most at the end', () {
    // 12 monthly buys of 100 from a starting price of 50,000, as the
    // simulator buys them.
    int sats(double rate) {
      var total = 0;
      for (var n = 0; n < 12; n++) {
        total += (100 / (50000 * pow(1 + rate, n / 12)) * 1e8).round();
      }
      return total;
    }

    final flat = DcaSimulator.endValue(sats(0), 50000, 12, 0);
    final rising = DcaSimulator.endValue(sats(0.4), 50000, 12, 0.4);
    expect(flat, closeTo(1200, 1));
    expect(rising, greaterThan(flat));
  });

  testWidgets('typing an amount updates the results', (tester) async {
    final controller = TextEditingController(text: '100');
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: DcaSimulator(
              btcPrice: 50000,
              controller: controller,
              years: 1,
              onYearsChanged: (_) {},
              currency: 'USD',
            ),
          ),
        ),
      ),
    );
    expect(find.text(r'$1,200'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '200');
    await tester.pump();
    expect(find.text(r'$2,400'), findsOneWidget);
  });
}
