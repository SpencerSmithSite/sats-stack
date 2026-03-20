import 'package:drift/drift.dart';
import '../database/database.dart';
import '../../shared/utils/hash_utils.dart';

class TransactionService {
  TransactionService(this._db);

  final AppDatabase _db;

  Stream<List<Transaction>> watchAll() {
    return (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .watch();
  }

  Future<List<Transaction>> getAll() {
    return (_db.select(_db.transactions)
          ..orderBy([(t) => OrderingTerm.desc(t.date)]))
        .get();
  }

  Future<void> add(TransactionsCompanion companion) {
    return _db.into(_db.transactions).insert(companion);
  }

  Future<void> deleteById(int id) {
    return (_db.delete(_db.transactions)
          ..where((t) => t.id.equals(id)))
        .go();
  }

  Future<void> update(TransactionsCompanion companion) {
    return (_db.update(_db.transactions)).replace(companion);
  }

  /// Finds all recurring transaction templates and inserts any instances that
  /// have come due since the last run. Safe to call on every app launch —
  /// the dedup hash prevents double-insertion.
  Future<void> generateDueRecurring() async {
    final recurring = await (_db.select(_db.transactions)
          ..where((t) => t.recurringPeriod.isNotNull()))
        .get();

    if (recurring.isEmpty) return;

    // For each series (identified by recurringAnchorDate + recurringPeriod),
    // find the most recently dated transaction so we know where to pick up from.
    final Map<String, Transaction> latestPerSeries = {};
    for (final tx in recurring) {
      if (tx.recurringAnchorDate == null) continue;
      final key =
          '${tx.recurringPeriod}_${tx.recurringAnchorDate!.millisecondsSinceEpoch}';
      final existing = latestPerSeries[key];
      if (existing == null || tx.date.isAfter(existing.date)) {
        latestPerSeries[key] = tx;
      }
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    for (final template in latestPerSeries.values) {
      var nextDue = _addPeriod(template.date, template.recurringPeriod!);

      while (!nextDue.isAfter(today)) {
        final salt =
            'recurring_${template.recurringAnchorDate!.millisecondsSinceEpoch}_${nextDue.millisecondsSinceEpoch}';
        final dedupHash = HashUtils.transactionDedupHash(
          date: nextDue,
          amount: template.amountFiat,
          description: template.description,
          salt: salt,
        );

        try {
          await _db.into(_db.transactions).insert(
                TransactionsCompanion.insert(
                  walletId: template.walletId,
                  date: nextDue,
                  description: template.description,
                  amountSats: template.amountSats,
                  amountFiat: template.amountFiat,
                  fiatCurrency: template.fiatCurrency,
                  category: Value(template.category),
                  source: 'manual',
                  notes: Value(template.notes),
                  dedupHash: dedupHash,
                  recurringPeriod: Value(template.recurringPeriod),
                  recurringAnchorDate: Value(template.recurringAnchorDate),
                ),
              );
        } catch (_) {
          // Unique constraint on dedupHash — already inserted, skip.
        }

        nextDue = _addPeriod(nextDue, template.recurringPeriod!);
      }
    }
  }

  DateTime _addPeriod(DateTime date, String period) {
    switch (period) {
      case 'weekly':
        return date.add(const Duration(days: 7));
      case 'monthly':
        // Clamp to last day of month if needed (e.g. Jan 31 → Feb 28)
        final m = date.month + 1;
        final y = date.year + (m > 12 ? 1 : 0);
        final month = m > 12 ? m - 12 : m;
        final maxDay = DateTime(y, month + 1, 0).day;
        return DateTime(y, month, date.day.clamp(1, maxDay));
      case 'yearly':
        return DateTime(date.year + 1, date.month, date.day);
      default:
        return date.add(const Duration(days: 30));
    }
  }
}
