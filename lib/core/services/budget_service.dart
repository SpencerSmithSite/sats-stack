import 'dart:async';
import 'package:drift/drift.dart' show Value;
import '../database/database.dart';
import '../models/budget_progress.dart';
import 'notification_service.dart';

class BudgetService {
  BudgetService(this._db);

  final AppDatabase _db;

  // ── Watches ──────────────────────────────────────────────────────────────────

  Stream<List<Budget>> watchAll() => _db.select(_db.budgets).watch();

  Future<List<Budget>> getAll() => _db.select(_db.budgets).get();

  // ── CRUD ─────────────────────────────────────────────────────────────────────

  /// Creates or updates the monthly budget for [categoryId].
  Future<void> upsert({
    required int categoryId,
    required double amountFiat,
  }) async {
    final existing = await (_db.select(_db.budgets)
          ..where((b) => b.categoryId.equals(categoryId)))
        .getSingleOrNull();

    if (existing != null) {
      await (_db.update(_db.budgets)..where((b) => b.id.equals(existing.id)))
          .write(BudgetsCompanion(amountFiat: Value(amountFiat)));
    } else {
      await _db.into(_db.budgets).insert(
        BudgetsCompanion.insert(
          categoryId: categoryId,
          amountFiat: amountFiat,
          period: 'monthly',
        ),
      );
    }
  }

  Future<void> deleteById(int id) {
    return (_db.delete(_db.budgets)..where((b) => b.id.equals(id))).go();
  }

  // ── Progress stream (reacts to budget + transaction changes) ─────────────────

  /// Emits a fresh [BudgetProgress] list whenever budgets or transactions change.
  Stream<List<BudgetProgress>> watchProgress(DateTime month) {
    StreamSubscription? budgetSub, txnSub;
    late StreamController<List<BudgetProgress>> controller;

    void update() async {
      if (controller.isClosed) return;
      controller.add(await getProgress(month));
    }

    controller = StreamController<List<BudgetProgress>>(
      onListen: () {
        budgetSub = _db.select(_db.budgets).watch().listen((_) => update());
        txnSub = _db.select(_db.transactions).watch().listen((_) => update());
        update();
      },
      onCancel: () {
        budgetSub?.cancel();
        txnSub?.cancel();
      },
    );

    return controller.stream;
  }

  Future<List<BudgetProgress>> getProgress(DateTime month) async {
    final budgets = await _db.select(_db.budgets).get();
    final categories = await _db.select(_db.categories).get();
    final allTxns = await _db.select(_db.transactions).get();

    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    final monthSpend = <int, double>{};
    for (final t in allTxns) {
      if (t.amountFiat >= 0) continue;
      if (t.date.isBefore(firstDay) || t.date.isAfter(lastDay)) continue;
      final cat = categories.where((c) => c.name == t.category).firstOrNull;
      if (cat != null) {
        monthSpend[cat.id] = (monthSpend[cat.id] ?? 0) + t.amountFiat.abs();
      }
    }

    final result = <BudgetProgress>[];
    for (final budget in budgets) {
      final cat = categories.where((c) => c.id == budget.categoryId).firstOrNull;
      if (cat == null) continue;
      result.add(BudgetProgress(
        budget: budget,
        category: cat,
        spentFiat: monthSpend[cat.id] ?? 0,
      ));
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
