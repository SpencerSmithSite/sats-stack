/// The spending breakdown shows pence when any figure has them.
///
/// Each bar rounded its own figure to whole units, so a £12.50 category read
/// £13 beside a list that otherwise added up.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/features/dashboard/widgets/spending_chart.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  Future<void> pump(WidgetTester tester, Map<String, double> spending) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: SpendingChart(spendingByCategory: spending, currency: 'GBP'),
          ),
        ),
      );

  testWidgets('one figure with pence gives every figure pence', (tester) async {
    await pump(tester, {'Food & Dining': 12.5, 'Transport': 30});
    expect(find.textContaining('£12.50'), findsOneWidget);
    expect(find.textContaining('£30.00'), findsOneWidget);
  });

  testWidgets('whole amounts stay whole', (tester) async {
    await pump(tester, {'Food & Dining': 12, 'Transport': 30});
    expect(find.textContaining('£12'), findsOneWidget);
    expect(find.textContaining('.00'), findsNothing);
  });
}
