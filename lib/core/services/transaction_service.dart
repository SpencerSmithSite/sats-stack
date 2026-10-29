import 'dart:math';

import 'package:drift/drift.dart';

import '../../shared/constants/app_constants.dart';
import '../../shared/utils/hash_utils.dart';
import '../database/database.dart';

class TransactionService {
  TransactionService(this._db);

  final AppDatabase _db;

  Stream<List<Transaction>> watchAll() {
    return (_db.select(_db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.date)])).watch();
  }

  Future<List<Transaction>> getAll() {
    return (_db.select(_db.transactions)
      ..orderBy([(t) => OrderingTerm.desc(t.date)])).get();
  }

  Future<void> add(TransactionsCompanion companion) {
    return _db.into(_db.transactions).insert(companion);
  }

  Future<void> deleteById(int id) {
    return (_db.delete(_db.transactions)..where((t) => t.id.equals(id))).go();
  }

  /// Writes the fields present in [companion] to the row with its `id`.
  ///
  /// Absent fields keep their stored values. Not `replace`: that resets every
  /// absent column to its default (rewriting `createdAt` on each edit) and
  /// throws for a companion that omits a required column like `walletId`.
  Future<void> update(TransactionsCompanion companion) {
    if (!companion.id.present) {
      throw ArgumentError.value(companion, 'companion', 'id is required');
    }
    return (_db.update(_db.transactions)
      ..where((t) => t.id.equals(companion.id.value))).write(companion);
  }

  /// A fresh id for a series the user is starting. Random rather than derived
  /// from the row, so nothing the user later edits can change it.
  static String newSeriesId() {
    final r = Random.secure();
    return List.generate(
      8,
      (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  /// Finds all recurring series and inserts any instances that have come due
  /// since the last run. Safe to call on every app launch — each series'
  /// cursor, and behind it the dedup hash, prevent double-insertion.
  ///
  /// [priceAt] prices each instance on its own date: a fiat series keeps its
  /// fiat amount and gets that day's sats, a Bitcoin one the reverse. Without
  /// it — or when a day's price cannot be had — the newest instance's figures
  /// are copied, which is what every instance used to get: a monthly £1,200
  /// rent stacked the same sats in a bull market as in a bear one.
  ///
  /// [now] exists for tests; production callers omit it.
  Future<void> generateDueRecurring({
    DateTime? now,
    Future<double?> Function(DateTime date, String currency)? priceAt,
  }) async {
    await _db.adoptLegacyRecurringSeries();

    final recurring =
        await (_db.select(_db.transactions)..where(
          (t) =>
              t.recurringPeriod.isNotNull() &
              t.recurringAnchorDate.isNotNull() &
              t.recurringSeriesId.isNotNull(),
        )).get();
    if (recurring.isEmpty) return;

    final seriesRows = <String, List<Transaction>>{};
    for (final tx in recurring) {
      (seriesRows[tx.recurringSeriesId!] ??= <Transaction>[]).add(tx);
    }

    final today = _dateOnly(now ?? DateTime.now());

    // ── Plan: which occurrences are due, per series ─────────────────────────
    final plans = <_SeriesPlan>[];
    for (final MapEntry(key: seriesId, value: rows) in seriesRows.entries) {
      // The newest instance carries the series' current figures, so editing
      // it is how the user changes what future instances look like.
      final template = rows.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
      final period = template.recurringPeriod!;
      final anchor = template.recurringAnchorDate!;

      // The resume point is the high-water mark, never just the latest
      // surviving row: deleting the most recent instance used to lower it and
      // the next launch brought that row straight back. With a stable series
      // id the cursor is authoritative — before v9 it had to be second-guessed
      // when a series looked re-created, and that let deleting every instance
      // but the anchor regenerate them all.
      final cursorKey = AppConstants.recurringCursorKey(seriesId);
      final cursorRow =
          await (_db.select(_db.appSettings)
            ..where((t) => t.key.equals(cursorKey))).getSingleOrNull();
      final cursor = int.tryParse(cursorRow?.value ?? '');

      var resumeFrom = cursor;
      if (resumeFrom == null) {
        // No cursor yet: a new series, or one from before cursors existed.
        // Resume after the highest occurrence it still has a row for.
        resumeFrom = 0;
        for (final row in rows) {
          final i = _occurrenceIndex(anchor, row.date, period);
          if (i > resumeFrom!) resumeFrom = i;
        }
      }

      // Dates are always derived from the anchor rather than by stepping
      // from the previous instance, so a clamped month (Jan 31 → Feb 28)
      // doesn't pull every later month back to the 28th. Calendar days are
      // compared: an instance due today is generated today even when the
      // series carries a time of day.
      final due = <DateTime>[];
      var n = resumeFrom! < 0 ? 1 : resumeFrom + 1;
      for (
        var next = _occurrence(anchor, period, n);
        !_dateOnly(next).isAfter(today);
        next = _occurrence(anchor, period, ++n)
      ) {
        due.add(next);
      }

      plans.add(
        _SeriesPlan(
          seriesId: seriesId,
          template: template,
          due: due,
          // n is now the first occurrence *not* generated. Written even when
          // nothing was due, so a series created today records its anchor and
          // a deletion cannot rewind past it.
          mark: n - 1,
          cursorKey: cursorKey,
          writeCursor: cursor == null || n - 1 > cursor,
        ),
      );
    }

    // ── Price each occurrence on its own day ────────────────────────────────
    //
    // Outside the write transaction: these can reach the network, and holding
    // the database lock across that would stall every screen.
    final prices = <(String, DateTime), double>{};
    if (priceAt != null) {
      for (final plan in plans) {
        for (final date in plan.due) {
          try {
            final price = await priceAt(date, plan.template.fiatCurrency);
            if (price != null && price > 0) {
              prices[(plan.seriesId, date)] = price;
            }
          } catch (_) {
            // Falls back to the template's figures below.
          }
        }
      }
    }

    // ── Write ───────────────────────────────────────────────────────────────
    //
    // One transaction so a launch that catches up on many missed periods
    // notifies stream listeners (dashboard, budgets, notifications) once
    // rather than once per inserted row.
    await _db.transaction(() async {
      for (final plan in plans) {
        final t = plan.template;
        for (final date in plan.due) {
          final price = prices[(plan.seriesId, date)];
          final sats =
              (price == null || t.isBitcoin)
                  ? t.amountSats
                  : (t.amountFiat / price * 100000000).round();
          final fiat =
              (price == null || !t.isBitcoin)
                  ? t.amountFiat
                  : t.amountSats / 100000000 * price;

          await _db
              .into(_db.transactions)
              .insert(
                TransactionsCompanion.insert(
                  walletId: t.walletId,
                  date: date,
                  description: t.description,
                  amountSats: sats,
                  amountFiat: fiat,
                  fiatCurrency: t.fiatCurrency,
                  category: Value(t.category),
                  source: 'manual',
                  isBitcoin: Value(t.isBitcoin),
                  notes: Value(t.notes),
                  dedupHash: recurringDedupHash(plan.seriesId, date),
                  recurringPeriod: Value(t.recurringPeriod),
                  recurringAnchorDate: Value(t.recurringAnchorDate),
                  recurringSeriesId: Value(plan.seriesId),
                ),
                // The unique dedupHash means "already inserted".
                mode: InsertMode.insertOrIgnore,
              );
        }

        if (plan.writeCursor) {
          await _db
              .into(_db.appSettings)
              .insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: plan.cursorKey,
                  value: plan.mark.toString(),
                ),
              );
        }
      }
    });
  }

  /// The dedup hash of [seriesId]'s occurrence on [due].
  ///
  /// Built only from what cannot change — the series and the due date — so
  /// an occurrence hashes the same however the series' description or amount
  /// is edited. It used to include both, which is how an edit let the same
  /// occurrence be inserted a second time.
  static String recurringDedupHash(String seriesId, DateTime due) =>
      HashUtils.transactionDedupHash(
        date: due,
        amount: 0,
        description: '',
        salt: 'recurring_${seriesId}_${due.millisecondsSinceEpoch}',
      );

  /// Ends [seriesId]: its rows stay, as one-off transactions, and no more are
  /// generated.
  ///
  /// There was no way to do this. Deleting every instance but the anchor
  /// regenerated them, and deleting the anchor too lost the history.
  Future<void> stopSeries(String seriesId) {
    return _db.transaction(() async {
      await (_db.update(_db.transactions)
        ..where((t) => t.recurringSeriesId.equals(seriesId))).write(
        const TransactionsCompanion(
          recurringPeriod: Value(null),
          recurringAnchorDate: Value(null),
          recurringSeriesId: Value(null),
        ),
      );
      await (_db.delete(_db.appSettings)..where(
        (t) => t.key.equals(AppConstants.recurringCursorKey(seriesId)),
      )).go();
    });
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// The [n]th occurrence of a series that started at [anchor] (n = 0 is the
  /// anchor itself), keeping the anchor's time of day.
  ///
  /// Uses calendar fields rather than adding a [Duration]: `add(days: 7)` is
  /// 168 hours, which across a DST change lands at 23:00 the day before and
  /// shifts a weekly series onto the wrong weekday for good.
  static DateTime _occurrence(DateTime anchor, String period, int n) {
    switch (period) {
      case 'weekly':
        return _onDay(anchor, anchor.year, anchor.month, anchor.day + 7 * n);
      case 'monthly':
        return _clampedToMonth(anchor, anchor.year, anchor.month + n);
      case 'yearly':
        // Clamped too, so Feb 29 falls back to Feb 28 rather than overflowing
        // into Mar 1.
        return _clampedToMonth(anchor, anchor.year + n, anchor.month);
      default:
        return _onDay(anchor, anchor.year, anchor.month, anchor.day + 30 * n);
    }
  }

  /// Which occurrence of the series [date] is — the inverse of [_occurrence].
  /// Tolerant of instances written before dates were anchor-derived (weekly
  /// ones an hour early after a DST change, monthly ones stuck on the 28th),
  /// so those series resume without generating a duplicate.
  static int _occurrenceIndex(DateTime anchor, DateTime date, String period) {
    switch (period) {
      case 'weekly':
        return (_dayDiff(anchor, date) / 7).round();
      case 'monthly':
        return (date.year - anchor.year) * 12 + date.month - anchor.month;
      case 'yearly':
        return date.year - anchor.year;
      default:
        return (_dayDiff(anchor, date) / 30).round();
    }
  }

  static int _dayDiff(DateTime from, DateTime to) =>
      DateTime.utc(
        to.year,
        to.month,
        to.day,
      ).difference(DateTime.utc(from.year, from.month, from.day)).inDays;

  static DateTime _onDay(DateTime time, int year, int month, int day) =>
      DateTime(
        year,
        month,
        day,
        time.hour,
        time.minute,
        time.second,
        time.millisecond,
        time.microsecond,
      );

  /// [anchor]'s day of month in [year]/[month] (month may overflow — DateTime
  /// normalises it), clamped to that month's length.
  static DateTime _clampedToMonth(DateTime anchor, int year, int month) {
    final first = DateTime(year, month);
    final maxDay = DateTime(first.year, first.month + 1, 0).day;
    return _onDay(anchor, first.year, first.month, anchor.day.clamp(1, maxDay));
  }
}

class _SeriesPlan {
  _SeriesPlan({
    required this.seriesId,
    required this.template,
    required this.due,
    required this.mark,
    required this.cursorKey,
    required this.writeCursor,
  });

  final String seriesId;
  final Transaction template;
  final List<DateTime> due;
  final int mark;
  final String cursorKey;
  final bool writeCursor;
}
