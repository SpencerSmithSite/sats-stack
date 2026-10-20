import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

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

  /// Finds all recurring transaction templates and inserts any instances that
  /// have come due since the last run. Safe to call on every app launch —
  /// the dedup hash prevents double-insertion.
  ///
  /// [now] exists for tests; production callers omit it.
  Future<void> generateDueRecurring({DateTime? now}) async {
    final recurring =
        await (_db.select(_db.transactions)
          ..where((t) => t.recurringPeriod.isNotNull())).get();

    if (recurring.isEmpty) return;

    // Group the instances into series.
    //
    // The identity includes the description and amount, not just the period
    // and anchor date: `showDatePicker` returns midnight, so two series
    // started on the same day had byte-identical anchors and collided — one of
    // them never generated at all, and they shared a cursor.
    final seriesRows = <String, List<Transaction>>{};
    for (final tx in recurring) {
      if (tx.recurringAnchorDate == null) continue;
      (seriesRows[seriesKey(tx)] ??= <Transaction>[]).add(tx);
    }

    final today = _dateOnly(now ?? DateTime.now());

    // One transaction so a launch that catches up on many missed periods
    // notifies stream listeners (dashboard, budgets, notifications) once
    // rather than once per inserted row.
    await _db.transaction(() async {
      for (final entry in seriesRows.entries) {
        final rows = entry.value;
        // Any row carries the series' shape; the newest is the conventional
        // one to copy from.
        final template = rows.reduce((a, b) => a.date.isAfter(b.date) ? a : b);
        final period = template.recurringPeriod!;
        final anchor = template.recurringAnchorDate!;
        // Dates are always derived from the anchor rather than by stepping
        // from the previous instance, so a clamped month (Jan 31 → Feb 28)
        // doesn't pull every later month back to the 28th.
        //
        // The resume point is the high-water mark, never just the latest
        // surviving row: deleting the most recent instance used to lower it
        // and the next launch brought that row straight back.
        final cursorKey = AppConstants.recurringCursorKey(entry.key);
        final cursorRow =
            await (_db.select(_db.appSettings)
              ..where((t) => t.key.equals(cursorKey))).getSingleOrNull();
        final cursor = int.tryParse(cursorRow?.value ?? '');

        // The highest occurrence the series still has a row for.
        var highestSurviving = 0;
        for (final row in rows) {
          final i = _occurrenceIndex(anchor, row.date, period);
          if (i > highestSurviving) highestSurviving = i;
        }

        // The cursor is authoritative, with one exception.
        //
        // Taking `max(cursor, latestSurviving)` — what this did before — meant
        // that editing one instance's date forward dragged the cursor with it
        // and every occurrence in between was skipped for good.
        //
        // The exception is a series whose only surviving row is its anchor
        // while the cursor sits above it: that is a series the user deleted
        // and re-created, and honouring the stale mark meant it never
        // generated again. A series where the newest instance alone was
        // deleted still has its middle instances, so it keeps the cursor and
        // the deleted row stays deleted.
        final resumeFrom =
            (cursor != null && highestSurviving > 0)
                ? cursor
                : highestSurviving;

        var n = resumeFrom + 1;
        if (n < 1) n = 1;
        var nextDue = _occurrence(anchor, period, n);
        final startedAt = n;

        // Compare calendar days: an instance due today is generated today even
        // when the series carries a time of day.
        while (!_dateOnly(nextDue).isAfter(today)) {
          final salt =
              'recurring_${anchor.millisecondsSinceEpoch}_${nextDue.millisecondsSinceEpoch}';
          final dedupHash = HashUtils.transactionDedupHash(
            date: nextDue,
            amount: template.amountFiat,
            description: template.description,
            salt: salt,
          );

          // insertOrIgnore: the unique dedupHash means "already inserted".
          await _db
              .into(_db.transactions)
              .insert(
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
                mode: InsertMode.insertOrIgnore,
              );

          n++;
          nextDue = _occurrence(anchor, period, n);
        }

        // n is now the first occurrence *not* generated, so n - 1 is the mark.
        // Written even when nothing was due, so a series created today records
        // its anchor and a deletion cannot rewind past it.
        final mark = n - 1;
        if (cursor == null || mark > cursor || startedAt == n) {
          await _db
              .into(_db.appSettings)
              .insertOnConflictUpdate(
                AppSettingsCompanion.insert(
                  key: cursorKey,
                  value: mark.toString(),
                ),
              );
        }
      }
    });
  }

  /// Identifies the series an instance belongs to.
  ///
  /// Period, anchor, description and amount — enough that two series started
  /// on the same day stay separate, and stable across launches so the cursor
  /// written under it is found again. Hashed because it becomes an
  /// `AppSettings` key.
  @visibleForTesting
  static String seriesKey(Transaction tx) {
    final raw =
        '${tx.recurringPeriod}|'
        '${tx.recurringAnchorDate!.millisecondsSinceEpoch}|'
        '${tx.description}|${tx.amountFiat}';
    return sha256.convert(utf8.encode(raw)).toString().substring(0, 16);
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
