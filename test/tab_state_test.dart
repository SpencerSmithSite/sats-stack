/// Pins that a tab keeps its state when you switch away and back.
///
/// The shell was a plain `ShellRoute`, which builds a different child type per
/// tab, so every switch destroyed the screen's State: a filter and search on
/// Transactions, the scroll position, the Stack period and DCA input, the
/// selected month on Budgets — all gone on returning, with the table re-queried
/// behind a full-screen spinner.
///
/// These drive the app's own router (`buildRouter`) with stub tabs, so they
/// test its branches, their order and the redirect — not a copy of them, which
/// is what this file used to build.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/app.dart';
import 'package:sats_stack/main.dart' as app;

/// A tab that counts taps, so lost State is visible as a reset counter.
class _CounterTab extends StatefulWidget {
  const _CounterTab(this.name);
  final String name;

  @override
  State<_CounterTab> createState() => _CounterTabState();
}

class _CounterTabState extends State<_CounterTab> {
  int count = 0;

  @override
  Widget build(BuildContext context) => Center(
    child: TextButton(
      onPressed: () => setState(() => count++),
      child: Text('${widget.name} $count'),
    ),
  );
}

Future<void> _pump(WidgetTester tester, {required bool aiEnabled}) async {
  app.aiEnabledNotifier = ValueNotifier(aiEnabled);
  app.onboardingCompleteNotifier = ValueNotifier(true);
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: buildRouter(tab: _CounterTab.new)),
  );
  await tester.pumpAndSettle();
}

Future<void> _tapTab(WidgetTester tester, String label) async {
  await tester.tap(
    find.descendant(of: find.byType(NavigationBar), matching: find.text(label)),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a tab keeps its state across a switch away and back', (
    tester,
  ) async {
    await _pump(tester, aiEnabled: true);

    await _tapTab(tester, 'Transactions');
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.textContaining('transactions'));
      await tester.pump();
    }
    expect(find.text('transactions 3'), findsOneWidget);

    await _tapTab(tester, 'Dashboard');
    await _tapTab(tester, 'Transactions');

    // A ShellRoute rebuilt this from scratch, so it read 0.
    expect(find.text('transactions 3'), findsOneWidget);
  });

  testWidgets('each tab keeps its own state independently', (tester) async {
    await _pump(tester, aiEnabled: true);

    await tester.tap(find.textContaining('dashboard'));
    await tester.pump();

    await _tapTab(tester, 'Stack');
    await tester.tap(find.textContaining('stack'));
    await tester.tap(find.textContaining('stack'));
    await tester.pump();

    await _tapTab(tester, 'Dashboard');
    expect(find.text('dashboard 1'), findsOneWidget);
    await _tapTab(tester, 'Stack');
    expect(find.text('stack 2'), findsOneWidget);
  });

  testWidgets('the AI tab is hidden when no provider can answer', (
    tester,
  ) async {
    await _pump(tester, aiEnabled: false);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(4));
    expect(find.text('AI'), findsNothing);
  });

  testWidgets('the AI tab appears when a provider becomes available', (
    tester,
  ) async {
    await _pump(tester, aiEnabled: false);
    app.aiEnabledNotifier.value = true;
    await tester.pumpAndSettle();
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.destinations, hasLength(5));
  });

  testWidgets('the highlighted tab matches the visible one', (tester) async {
    // Branch index and nav-bar index must agree — the AI branch is last so
    // that hiding it shifts nothing.
    await _pump(tester, aiEnabled: true);
    await _tapTab(tester, 'Budgets');
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 2);
    expect(find.textContaining('budgets'), findsOneWidget);
  });

  testWidgets('losing the AI tab while on it moves to the dashboard', (
    tester,
  ) async {
    // The app's own redirect — a copied router could not test it.
    await _pump(tester, aiEnabled: true);
    await _tapTab(tester, 'AI');
    expect(find.text('ai 0'), findsOneWidget);

    app.aiEnabledNotifier.value = false;
    await tester.pumpAndSettle();

    expect(find.text('dashboard 0'), findsOneWidget);
    final bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(bar.selectedIndex, 0);
  });
}
