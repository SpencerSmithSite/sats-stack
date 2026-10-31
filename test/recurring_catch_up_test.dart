/// Recurring transactions are generated while the app stays open, not only
/// at a cold start (audit D-3).
library;

import 'dart:async';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/recurring_catch_up.dart';

void main() {
  testWidgets('runs at start, then just after midnight', (tester) async {
    var runs = 0;
    var clock = DateTime(2026, 10, 31, 23, 59);
    final catchUp = RecurringCatchUp(() async => runs++, now: () => clock);

    catchUp.start();
    await tester.pump();
    expect(runs, 1);

    clock = DateTime(2026, 11, 1, 0, 0, 30);
    await tester.pump(const Duration(seconds: 65));
    expect(runs, 2);

    // And again the next night — by the calendar, not every 24 hours: where
    // daylight saving ends that night, midnight to midnight is 25 hours.
    clock = DateTime(2026, 11, 2, 0, 0, 30);
    await tester.pump(const Duration(hours: 26));
    expect(runs, 3);
    catchUp.dispose();
  });

  testWidgets('runs on every return to the app', (tester) async {
    var runs = 0;
    final catchUp = RecurringCatchUp(
      () async => runs++,
      now: () => DateTime(2026, 10, 31, 12),
    );
    catchUp.start();
    await tester.pump();

    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
      AppLifecycleState.hidden,
      AppLifecycleState.inactive,
      AppLifecycleState.resumed,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    expect(runs, 2);
    catchUp.dispose();
  });

  testWidgets('a run already in progress is joined, not repeated', (
    tester,
  ) async {
    var runs = 0;
    final gate = Completer<void>();
    final catchUp = RecurringCatchUp(() {
      runs++;
      return gate.future;
    }, now: () => DateTime(2026, 10, 31, 12));

    catchUp.start();
    unawaited(catchUp.run());
    unawaited(catchUp.run());
    expect(runs, 1);

    gate.complete();
    await tester.pump();
    unawaited(catchUp.run());
    expect(runs, 2);
    catchUp.dispose();
  });

  testWidgets('a failed run does not stop the next one', (tester) async {
    var runs = 0;
    final catchUp = RecurringCatchUp(() async {
      runs++;
      throw StateError('database busy');
    }, now: () => DateTime(2026, 10, 31, 12));

    catchUp.start();
    await tester.pump();
    await catchUp.run();
    expect(runs, 2);
    catchUp.dispose();
  });
}
