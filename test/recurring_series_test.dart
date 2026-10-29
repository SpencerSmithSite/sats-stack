/// A recurring series has a stable identity.
///
/// Series used to be identified by their period, anchor, description and
/// amount. Editing an instance therefore started a new series and the old one
/// regenerated — duplicates; renaming the anchor recreated nearly every past
/// instance. There was no way to stop a series, two identical series in two
/// accounts were one, and every instance copied the anchor's sats rather than
/// being priced on its own date.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

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

  final anchor = DateTime(2026, 1, 15);

  /// A series as AddTransactionSheet creates one.
  Future<String> start({
    String description = 'Rent',
    double fiat = -1200,
    int sats = -1000000,
    bool isBitcoin = false,
    int? wallet,
  }) async {
    final id = TransactionService.newSeriesId();
    await service.add(
      TransactionsCompanion.insert(
        walletId: wallet ?? walletId,
        date: anchor,
        description: description,
        amountSats: sats,
        amountFiat: fiat,
        fiatCurrency: 'USD',
        source: 'manual',
        isBitcoin: Value(isBitcoin),
        dedupHash: 'anchor-$id',
        recurringPeriod: const Value('monthly'),
        recurringAnchorDate: Value(anchor),
        recurringSeriesId: Value(id),
      ),
    );
    return id;
  }

  Future<List<Transaction>> rows() =>
      (db.select(db.transactions)
        ..orderBy([(t) => OrderingTerm.asc(t.date)])).get();

  Future<void> rename(int id, String description, {double? fiat}) =>
      service.update(
        TransactionsCompanion(
          id: Value(id),
          description: Value(description),
          amountFiat: fiat == null ? const Value.absent() : Value(fiat),
        ),
      );

  group('editing does not split a series', () {
    test(
      'renaming an instance: no duplicates, and the future follows',
      () async {
        await start();
        await service.generateDueRecurring(now: DateTime(2026, 3, 20));
        final march = (await rows()).last;
        await rename(march.id, 'Rent (new flat)', fiat: -1350);

        await service.generateDueRecurring(now: DateTime(2026, 5, 20));

        final all = await rows();
        expect(all.map((t) => t.date), [
          DateTime(2026, 1, 15),
          DateTime(2026, 2, 15),
          DateTime(2026, 3, 15),
          DateTime(2026, 4, 15),
          DateTime(2026, 5, 15),
        ]);
        expect(
          all.skip(3).map((t) => t.description),
          everyElement('Rent (new flat)'),
        );
        expect(all.skip(3).map((t) => t.amountFiat), everyElement(-1350));
      },
    );

    test('renaming the anchor recreates nothing', () async {
      await start();
      await service.generateDueRecurring(now: DateTime(2026, 6, 20));
      final first = (await rows()).first;
      await rename(first.id, 'Rent!');

      await service.generateDueRecurring(now: DateTime(2026, 6, 20));

      expect(await rows(), hasLength(6));
    });

    test('deleting every instance but the anchor keeps them deleted', () async {
      await start();
      await service.generateDueRecurring(now: DateTime(2026, 6, 20));
      for (final t in (await rows()).skip(1)) {
        await service.deleteById(t.id);
      }

      await service.generateDueRecurring(now: DateTime(2026, 6, 20));
      expect(await rows(), hasLength(1));

      // …and the series still carries on from there.
      await service.generateDueRecurring(now: DateTime(2026, 7, 20));
      expect((await rows()).map((t) => t.date), [
        anchor,
        DateTime(2026, 7, 15),
      ]);
    });
  });

  test('a stopped series keeps its rows and adds no more', () async {
    final id = await start();
    await service.generateDueRecurring(now: DateTime(2026, 3, 20));
    await service.stopSeries(id);

    await service.generateDueRecurring(now: DateTime(2026, 9, 20));

    final all = await rows();
    expect(all, hasLength(3));
    for (final t in all) {
      expect(t.recurringPeriod, isNull);
      expect(t.recurringSeriesId, isNull);
    }
    final cursor =
        await (db.select(db.appSettings)..where(
          (t) => t.key.equals(AppConstants.recurringCursorKey(id)),
        )).getSingleOrNull();
    expect(cursor, isNull);
  });

  group('each instance is priced on its own date', () {
    Future<double?> price(DateTime date, String currency) async {
      expect(currency, 'USD');
      return date.month == 2 ? 100000 : (date.month == 3 ? null : 50000);
    }

    test('a fiat series keeps its fiat and gets that day\'s sats', () async {
      await start(fiat: -1000, sats: -1);
      await service.generateDueRecurring(
        now: DateTime(2026, 4, 20),
        priceAt: price,
      );

      final all = await rows();
      expect(all.map((t) => t.amountFiat), everyElement(-1000));
      expect(all[1].amountSats, -1000000); // $1,000 at $100k
      expect(all[2].amountSats, -1, reason: 'no price: the template is kept');
      expect(all[3].amountSats, -2000000); // $1,000 at $50k
    });

    test('a Bitcoin series keeps its sats and gets that day\'s fiat', () async {
      await start(fiat: -1, sats: -100000, isBitcoin: true);
      await service.generateDueRecurring(
        now: DateTime(2026, 2, 20),
        priceAt: price,
      );

      final feb = (await rows()).last;
      expect(feb.isBitcoin, isTrue);
      expect(feb.amountSats, -100000);
      expect(feb.amountFiat, closeTo(-100, 1e-9));
    });

    test('a failed lookup falls back rather than aborting', () async {
      await start();
      await service.generateDueRecurring(
        now: DateTime(2026, 3, 20),
        priceAt: (_, _) async => throw const SocketException('offline'),
      );
      expect(await rows(), hasLength(3));
    });
  });

  group('series written before v9', () {
    Future<void> legacy({
      required String description,
      required int wallet,
      required DateTime date,
      required String hash,
    }) => db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: date,
            description: description,
            amountSats: -1000000,
            amountFiat: -1200,
            fiatCurrency: 'USD',
            source: 'manual',
            dedupHash: hash,
            recurringPeriod: const Value('monthly'),
            recurringAnchorDate: Value(anchor),
          ),
        );

    test('two identical series in two accounts stay two', () async {
      final second = await db
          .into(db.wallets)
          .insert(
            WalletsCompanion.insert(
              label: 'Joint',
              type: 'manual',
              color: '#1D9E75',
            ),
          );
      await legacy(
        description: 'Rent',
        wallet: walletId,
        date: anchor,
        hash: 'a',
      );
      await legacy(
        description: 'Rent',
        wallet: second,
        date: anchor,
        hash: 'b',
      );

      await service.generateDueRecurring(now: DateTime(2026, 3, 20));

      final all = await rows();
      expect(all.where((t) => t.walletId == walletId), hasLength(3));
      expect(all.where((t) => t.walletId == second), hasLength(3));
    });

    test('keep their cursor, so a deleted instance stays deleted', () async {
      await legacy(
        description: 'Rent',
        wallet: walletId,
        date: anchor,
        hash: 'a',
      );
      await legacy(
        description: 'Rent',
        wallet: walletId,
        date: DateTime(2026, 2, 15),
        hash: 'b',
      );
      // March was generated, then deleted, under the old key.
      final old = AppDatabase.legacySeriesKey((await rows()).first);
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppConstants.recurringCursorKey(old),
              value: '2',
            ),
          );

      await service.generateDueRecurring(now: DateTime(2026, 3, 20));

      final all = await rows();
      expect(all, hasLength(2));
      final id = all.first.recurringSeriesId!;
      expect(all.last.recurringSeriesId, id);
      final keys = (await db.select(db.appSettings).get()).map((s) => s.key);
      expect(keys, contains(AppConstants.recurringCursorKey(id)));
      expect(keys, isNot(contains(AppConstants.recurringCursorKey(old))));
    });

    test('the v9 upgrade gives them ids', () async {
      final dir = await Directory.systemTemp.createTemp('v9');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');

      final v8 = AppDatabase.forTesting(NativeDatabase(file));
      final wallet = (await v8.select(v8.wallets).getSingle()).id;
      await v8.customStatement(
        'ALTER TABLE transactions DROP COLUMN recurring_series_id',
      );
      await v8.customStatement('ALTER TABLE budgets DROP COLUMN currency');
      await v8.customStatement(
        'INSERT INTO transactions (wallet_id, date, description, '
        'amount_sats, amount_fiat, fiat_currency, source, is_bitcoin, '
        'dedup_hash, created_at, recurring_period, recurring_anchor_date) '
        'VALUES (?, ?, ?, -1, -1200, ?, ?, 0, ?, 0, ?, ?)',
        [
          wallet,
          anchor.millisecondsSinceEpoch ~/ 1000,
          'Rent',
          'USD',
          'manual',
          'a',
          'monthly',
          anchor.millisecondsSinceEpoch ~/ 1000,
        ],
      );
      await v8.customStatement('PRAGMA user_version = 8');
      await v8.close();

      final upgraded = AppDatabase.forTesting(NativeDatabase(file));
      final row = await upgraded.select(upgraded.transactions).getSingle();
      expect(row.recurringSeriesId, isNotNull);
      expect(row.recurringAnchorDate, anchor);
      await upgraded.close();
    });
  });
}
