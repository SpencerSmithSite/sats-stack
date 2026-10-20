import 'dart:async';

// Comparison operators on columns (`isBiggerOrEqualValue`) come from drift
// extensions, which a `show` clause would hide.
import 'package:drift/drift.dart';

import '../../shared/utils/date_range.dart';
import '../database/database.dart';
import '../models/budget_progress.dart';
import '../models/fx_rates.dart';
import 'notification_service.dart';

class BudgetService {
  /// [rates] converts spending into the display currency before it is
  /// compared with a budget — see [DashboardService] for why it is a function.
  BudgetService(this._db, {FxRates Function()? rates})
    : _rates = rates ?? (() => const FxRates.passthrough());

  final AppDatabase _db;
  final FxRates Function() _rates;

  // ── Watches ──────────────────────────────────────────────────────────────────

  Stream<List<Budget>> watchAll() => _db.select(_db.budgets).watch();

  Future<List<Budget>> getAll() => _db.select(_db.budgets).get();

  // ── CRUD ─────────────────────────────────────────────────────────────────────

  /// Creates or updates the monthly budget for [categoryId].
  ///
  /// The read and the write are one transaction, and `budgets.categoryId`
  /// carries a unique index. Before both, double-tapping Save raced two
  /// inserts through the gap, and from then on every upsert for that category
  /// threw `StateError` out of `getSingleOrNull` — the budget could not be
  /// edited again without clearing the data.
  Future<void> upsert({
    required int categoryId,
    required double amountFiat,
  }) async {
    await _db.transaction(() async {
      final existing =
          await (_db.select(_db.budgets)
            ..where((b) => b.categoryId.equals(categoryId))).getSingleOrNull();

      if (existing != null) {
        await (_db.update(_db.budgets)..where(
          (b) => b.id.equals(existing.id),
        )).write(BudgetsCompanion(amountFiat: Value(amountFiat)));
      } else {
        await _db
            .into(_db.budgets)
            .insert(
              BudgetsCompanion.insert(
                categoryId: categoryId,
                amountFiat: amountFiat,
                period: 'monthly',
              ),
            );
      }
    });
  }

  Future<void> deleteById(int id) {
    return (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
  }

  // ── Progress stream (reacts to budget + transaction changes) ─────────────────

  /// Emits a fresh [BudgetProgress] list whenever budgets or transactions change.
  ///
  /// Reads are coalesced and serialised. Both watches emit immediately on
  /// listen and a single insert notifies both, so the previous version — two
  /// listeners plus an explicit call, each firing [getProgress] straight away —
  /// ran the whole aggregate three times for one change, and a burst of
  /// inserts ran it once per row.
  Stream<List<BudgetProgress>> watchProgress(DateTime month) {
    StreamSubscription<void>? budgetSub, txnSub;
    late StreamController<List<BudgetProgress>> controller;

    var queued = false; // a read is scheduled for the next microtask
    var reading = false; // a read is in flight
    var again = false; // something changed while that read was in flight

    Future<void> read() async {
      if (reading) {
        again = true;
        return;
      }
      reading = true;
      try {
        do {
          again = false;
          final progress = await getProgress(month);
          if (controller.isClosed) return;
          controller.add(progress);
        } while (again);
      } finally {
        reading = false;
      }
    }

    void schedule() {
      if (queued || controller.isClosed) return;
      queued = true;
      // A microtask, so the two immediate emissions on listen collapse into
      // one read rather than two.
      scheduleMicrotask(() {
        queued = false;
        read();
      });
    }

    controller = StreamController<List<BudgetProgress>>(
      onListen: () {
        budgetSub = _db.select(_db.budgets).watch().listen((_) => schedule());
        txnSub = _db.select(_db.transactions).watch().listen((_) => schedule());
      },
      onCancel: () async {
        await budgetSub?.cancel();
        await txnSub?.cancel();
        // Closing matters: `controller.isClosed` guards every add above, and
        // without this it was always false — a dead guard on a controller that
        // was never released.
        await controller.close();
      },
    );

    return controller.stream;
  }

  Future<List<BudgetProgress>> getProgress(DateTime month) async {
    final range = DateRange.month(month);

    final budgets = await _db.select(_db.budgets).get();
    final categories = await _db.select(_db.categories).get();
    // Filtered in SQL, against the v7 index on `date`. This used to read every
    // transaction ever recorded to total up one month, on every change, and it
    // runs on the UI isolate.
    final monthTxns =
        await (_db.select(_db.transactions)
              ..where((t) => t.date.isBiggerOrEqualValue(range.start))
              ..where((t) => t.date.isSmallerThanValue(range.end))
              ..where((t) => t.amountFiat.isSmallerThanValue(0)))
            .get();

    final categoryIdByName = {for (final c in categories) c.name: c.id};
    final categoryById = {for (final c in categories) c.id: c};

    // Converted before it is compared with a budget. A £500 Food budget used
    // to be measured against pounds and dollars added together.
    final fx = _rates();
    final monthSpend = <int, double>{};
    for (final t in monthTxns) {
      final id = categoryIdByName[t.category];
      if (id == null) continue;
      final spent = fx.convert(t.amountFiat.abs(), t.fiatCurrency);
      if (spent == null) continue;
      monthSpend[id] = (monthSpend[id] ?? 0) + spent;
    }

    final result = <BudgetProgress>[];
    for (final budget in budgets) {
      final cat = categoryById[budget.categoryId];
      if (cat == null) continue;
      result.add(
        BudgetProgress(
          budget: budget,
          category: cat,
          spentFiat: monthSpend[cat.id] ?? 0,
        ),
      );
    }

    // Sort: over-budget first, then by spent desc
    result.sort((a, b) {
      if (a.isOverBudget && !b.isOverBudget) return -1;
      if (!a.isOverBudget && b.isOverBudget) return 1;
      return b.spentFiat.compareTo(a.spentFiat);
    });

    return result;
  }

  // ── Notifications ─────────────────────────────────────────────────────────

  /// Checks the current month's budget progress and fires a local notification
  /// for any category that is ≥ 80 % spent (warning) or > 100 % spent
  /// (overspend). The [NotificationService] deduplicates within a session so
  /// this can be called repeatedly without spamming the user.
  Future<void> checkAndNotify({
    required NotificationService notifications,
    required String currency,
  }) async {
    final month = DateTime.now();
    final progress = await getProgress(month);

    for (final p in progress) {
      if (p.isOverBudget) {
        await notifications.showBudgetOverspend(
          categoryId: p.category.id,
          categoryName: p.category.name,
          overBy: p.spentFiat - p.budget.amountFiat,
          budgetAmount: p.budget.amountFiat,
          currency: currency,
        );
      } else if (p.progress >= 0.8) {
        await notifications.showBudgetWarning(
          categoryId: p.category.id,
          categoryName: p.category.name,
          percentUsed: (p.progress * 100).round(),
          budgetAmount: p.budget.amountFiat,
          currency: currency,
        );
      }
    }
  }
}
