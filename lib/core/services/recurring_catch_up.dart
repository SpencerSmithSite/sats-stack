import 'dart:async';

import 'package:flutter/widgets.dart';

/// Keeps recurring transactions generated while the app stays open.
///
/// They come due by the calendar, but were generated only at a cold start. A
/// phone resumes a suspended app for days or weeks without one, and a desktop
/// window can stay open as long, so the rent or the salary simply did not
/// appear — and budgets, the dashboard and overspend alerts all under-counted
/// until the next launch (audit D-3).
///
/// So [generate] runs at [start], on every return to the app, and just after
/// each local midnight while it is in the foreground (timers do not run while
/// it is suspended; the resume covers that). Repeating it is safe: each
/// series' cursor and dedup hash stop an instance being written twice. Runs
/// that would overlap share the one in flight.
class RecurringCatchUp {
  RecurringCatchUp(this._generate, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Future<void> Function() _generate;
  final DateTime Function() _now;

  Future<void>? _running;
  Timer? _midnight;
  AppLifecycleListener? _lifecycle;

  void start() {
    run();
    _lifecycle = AppLifecycleListener(onResume: run);
    _scheduleMidnight();
  }

  /// Generates what has come due, or joins a run already in progress.
  Future<void> run() =>
      _running ??= _generate()
          .catchError((Object _) {})
          .whenComplete(() => _running = null);

  void _scheduleMidnight() {
    final now = _now();
    // A few seconds past, so the new day has unambiguously begun.
    final next = DateTime(now.year, now.month, now.day + 1, 0, 0, 5);
    _midnight?.cancel();
    _midnight = Timer(next.difference(now), () {
      run();
      _scheduleMidnight();
    });
  }

  void dispose() {
    _midnight?.cancel();
    _lifecycle?.dispose();
  }
}
