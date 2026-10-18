import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/transaction_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late TransactionService service;
  late int walletId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = TransactionService(db);
    walletId = (await db.select(db.wallets).getSingle()).id;
  });

  tearDown(() => db.close());

  Future<int> insert({
    required DateTime date,
    String description = 'Rent',
    double amountFiat = -1000,
    String? period,
    DateTime? anchor,
    String hash = 'seed',
    bool isBitcoin = false,
  }) {
    return db.into(db.transactions).insert(TransactionsCompanion.insert(
          walletId: walletId,
          date: date,
          description: description,
          amountSats: -1000000,
          amountFiat: amountFiat,
          fiatCurrency: 'USD',
          source: 'manual',
          isBitcoin: Value(isBitcoin),
          dedupHash: hash,
          recurringPeriod: Value(period),
          recurringAnchorDate: Value(anchor),
        ));
  }

  Future<List<DateTime>> dates() async {
    final rows = await (db.select(db.transactions)
          ..orderBy([(t) => OrderingTerm.asc(t.date)]))
        .get();
    return rows.map((t) => t.date).toList();
  }

  group('update', () {
    test('keeps columns absent from the companion, including createdAt',
        () async {
      final id = await insert(date: DateTime(2026, 3, 1), isBitcoin: true);
      final before = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();

      // Same shape as AddTransactionSheet's edit path: no walletId,
      // fiatCurrency, source, dedupHash, isBitcoin or createdAt.
      await service.update(TransactionsCompanion(
        id: Value(id),
        description: const Value('Rent (edited)'),
        amountFiat: const Value(-1200),
      ));

      final after = await (db.select(db.transactions)
            ..where((t) => t.id.equals(id)))
          .getSingle();
      expect(after.description, 'Rent (edited)');
      expect(after.amountFiat, -1200);
      expect(after.createdAt, before.createdAt);
      expect(after.isBitcoin, isTrue);
      expect(after.dedupHash, 'seed');
      expect(after.walletId, walletId);
    });

    test('writes explicit nulls', () async {
      final anchor = DateTime(2026, 3, 1);
      final id =
          await insert(date: anchor, period: 'monthly', anchor: anchor);
      await service.update(TransactionsCompanion(
        id: Value(id),
        recurringPeriod: const Value(null),
        recurringAnchorDate: const Value(null),
      ));
      final after = await db.select(db.transactions).getSingle();
      expect(after.recurringPeriod, isNull);
      expect(after.recurringAnchorDate, isNull);
    });
  });

  group('generateDueRecurring', () {
    test('monthly series anchored on the 31st keeps returning to month-end',
        () async {
      final anchor = DateTime(2026, 1, 31);
      await insert(date: anchor, period: 'monthly', anchor: anchor);

      await service.generateDueRecurring(now: DateTime(2026, 5, 31, 9));

      expect(await dates(), [
        DateTime(2026, 1, 31),
        DateTime(2026, 2, 28),
        DateTime(2026, 3, 31), // previously drifted to Mar 28 …
        DateTime(2026, 4, 30), // … and every month after it
        DateTime(2026, 5, 31),
      ]);
    });

    test('resumes a series that already drifted without a duplicate',
        () async {
      final anchor = DateTime(2026, 1, 31);
      await insert(date: anchor, period: 'monthly', anchor: anchor, hash: 'a');
      await insert(
          date: DateTime(2026, 2, 28),
          period: 'monthly',
          anchor: anchor,
          hash: 'b');
      // Written by the old step-from-previous logic.
      await insert(
          date: DateTime(2026, 3, 28),
          period: 'monthly',
          anchor: anchor,
          hash: 'c');

      await service.generateDueRecurring(now: DateTime(2026, 4, 30));

      final all = await dates();
      expect(all.where((d) => d.month == 3), hasLength(1));
      expect(all.last, DateTime(2026, 4, 30));
    });

    test('yearly Feb 29 clamps to Feb 28 instead of overflowing to Mar 1',
        () async {
      final anchor = DateTime(2024, 2, 29);
      await insert(date: anchor, period: 'yearly', anchor: anchor);

      await service.generateDueRecurring(now: DateTime(2028, 3, 1));

      expect(await dates(), [
        DateTime(2024, 2, 29),
        DateTime(2025, 2, 28),
        DateTime(2026, 2, 28),
        DateTime(2027, 2, 28),
        DateTime(2028, 2, 29),
      ]);
    });

    test('weekly series keeps its weekday and time of day across DST', () async {
      // Spans both 2026 DST transitions in the EU and North America. In a
      // zone without DST this is trivially true; in one with DST, stepping
      // by Duration(days: 7) used to land an hour off.
      final anchor = DateTime(2026, 3, 1);
      await insert(date: anchor, period: 'weekly', anchor: anchor);

      await service.generateDueRecurring(now: DateTime(2026, 11, 30));

      final all = await dates();
      expect(all.length, greaterThan(30));
      for (final d in all) {
        expect(d.weekday, anchor.weekday, reason: '$d');
        expect(d.hour, 0, reason: '$d');
      }
    });

    test('an instance due today is generated even when it carries a time',
        () async {
      // AddTransactionSheet defaults the date to DateTime.now(), so series
      // often have a time of day.
      final anchor = DateTime(2026, 6, 1, 14, 30);
      await insert(date: anchor, period: 'weekly', anchor: anchor);

      await service.generateDueRecurring(now: DateTime(2026, 6, 8, 9));

      expect(await dates(), [anchor, DateTime(2026, 6, 8, 14, 30)]);
    });

    test('is idempotent', () async {
      final anchor = DateTime(2026, 1, 15);
      await insert(date: anchor, period: 'monthly', anchor: anchor);
      final now = DateTime(2026, 6, 20);

      await service.generateDueRecurring(now: now);
      final first = await dates();
      await service.generateDueRecurring(now: now);

      expect(await dates(), first);
      expect(first, hasLength(6));
    });
  });
}
