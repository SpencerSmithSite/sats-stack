/// Pins the deduplication-hash contract.
///
/// `Transactions.dedupHash` is UNIQUE and every insert path uses
/// `InsertMode.insertOrIgnore`, so a hash collision is not an error — it is a
/// silently dropped transaction. Four callers choose four different salts, and
/// each choice means something specific:
///
/// | caller | salt | intent |
/// |---|---|---|
/// | statement import | `source_<id>`, plus `#n` for the n-th identical row in a file | re-importing into a source dedupes; two accounts, or two identical rows, do not |
/// | manual entry | microsecond timestamp | an intentional duplicate must be kept |
/// | recurring series | `recurring_<seriesId>_<due>`, over a blank description and zero amount | one row per due date per series, however the series is edited |
/// | xpub sync | `xpub_<txid>`, then `HashUtils.scopedToWallet` | one row per on-chain transaction, per wallet |
///
/// Nothing asserted the distinctions, and getting one wrong is invisible until
/// a user notices a missing row. The audit found exactly that: the import path
/// hashed an unsigned amount, so a charge and its same-day refund collided and
/// the refund vanished.
library;

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/transaction_service.dart';
import 'package:sats_stack/shared/utils/hash_utils.dart';

void main() {
  final date = DateTime(2026, 3, 15);

  String importHash({
    required double amount,
    String description = 'AMAZON MKTPLACE',
    int sourceId = 1,
    int occurrence = 0,
    DateTime? on,
  }) => HashUtils.transactionDedupHash(
    date: on ?? date,
    amount: amount,
    description: description,
    salt: ImportService.importDedupSalt(sourceId, occurrence),
  );

  group('statement import: the same row dedupes, different rows do not', () {
    test('re-importing an identical row produces an identical hash', () {
      // The whole point of the empty-ish, stable salt: import the same
      // statement twice and the second pass writes nothing.
      expect(importHash(amount: -49.99), importHash(amount: -49.99));
    });

    test('a charge and its same-day refund are different rows', () {
      // The audit's finding. The hash used `tx.amount`, documented as "always
      // positive", so these two collided and insertOrIgnore dropped the
      // refund while the summary still counted it as imported.
      expect(importHash(amount: -49.99), isNot(importHash(amount: 49.99)));
    });

    test('the same figure in two accounts is two rows', () {
      // RENT 1500.00 on the 1st, in two different accounts. Scoped to the
      // source, not the wallet: every source writes to the same wallet.
      expect(
        importHash(amount: -1500, description: 'RENT', sourceId: 1),
        isNot(importHash(amount: -1500, description: 'RENT', sourceId: 2)),
      );
    });

    test('two identical rows in one file are two rows', () {
      // Two bus fares, same day, same amount.
      expect(
        importHash(amount: -2.8, occurrence: 0),
        isNot(importHash(amount: -2.8, occurrence: 1)),
      );
    });

    test('amount, date and description each change the hash', () {
      final base = importHash(amount: -10);
      expect(base, isNot(importHash(amount: -10.01)));
      expect(base, isNot(importHash(amount: -10, on: DateTime(2026, 3, 16))));
      expect(base, isNot(importHash(amount: -10, description: 'TESCO')));
    });
  });

  group('manual entry: an intentional duplicate is kept', () {
    test('two identical manual entries get different hashes', () {
      // Buying the same coffee twice in one day is two transactions, so the
      // salt is a timestamp rather than something derived from the content.
      String manual(int micros) => HashUtils.transactionDedupHash(
        date: date,
        amount: -4.5,
        description: 'Coffee',
        salt: micros.toString(),
      );

      expect(manual(1760000000000001), isNot(manual(1760000000000002)));
    });
  });

  group('recurring: idempotent per due date', () {
    String recurring(String series, DateTime due) =>
        TransactionService.recurringDedupHash(series, due);

    test('generating the same due date twice is one row', () {
      // generateDueRecurring runs on every launch; it must be safe to re-run.
      expect(
        recurring('rent', DateTime(2026, 3, 15)),
        recurring('rent', DateTime(2026, 3, 15)),
      );
    });

    test('each due date is its own row', () {
      expect(
        recurring('rent', DateTime(2026, 3, 15)),
        isNot(recurring('rent', DateTime(2026, 4, 15))),
      );
    });

    test('two series with the same figures stay separate', () {
      // Two monthly £1,200 payments due the same day are two series.
      expect(
        recurring('rent', DateTime(2026, 3, 15)),
        isNot(recurring('loan', DateTime(2026, 3, 15))),
      );
    });

    test('is the documented formula', () {
      final due = DateTime(2026, 3, 15);
      expect(
        recurring('rent', due),
        HashUtils.transactionDedupHash(
          date: due,
          amount: 0,
          description: '',
          salt: 'recurring_rent_${due.millisecondsSinceEpoch}',
        ),
      );
    });
  });

  group('xpub: one row per on-chain transaction', () {
    String chain(String txid, int netSats) => HashUtils.transactionDedupHash(
      date: date,
      amount: netSats.toDouble(),
      description: 'BTC ${txid.substring(0, 8)}',
      salt: 'xpub_$txid',
    );

    const txid = 'a1b2c3d4e5f60718293a4b5c6d7e8f90';

    test('rescanning the same transaction is one row', () {
      expect(chain(txid, 150000), chain(txid, 150000));
    });

    test('two transactions are two rows', () {
      expect(
        chain(txid, 150000),
        isNot(chain('f0e1d2c3b4a59687786950413223140', 150000)),
      );
    });
  });

  group('the four salts cannot collide with each other', () {
    test('identical date, amount and description still hash differently', () {
      // A £1,200 payment on the same day could plausibly arrive from all four
      // paths. Each must remain its own row.
      const amount = -1200.0;
      const description = 'Rent';
      final hashes = {
        'import': HashUtils.transactionDedupHash(
          date: date,
          amount: amount,
          description: description,
          salt: 'wallet_1',
        ),
        'manual': HashUtils.transactionDedupHash(
          date: date,
          amount: amount,
          description: description,
          salt: '1760000000000001',
        ),
        'recurring': HashUtils.transactionDedupHash(
          date: date,
          amount: amount,
          description: description,
          salt: 'recurring_1_2',
        ),
        'xpub': HashUtils.transactionDedupHash(
          date: date,
          amount: amount,
          description: description,
          salt: 'xpub_abc',
        ),
      };

      expect(hashes.values.toSet(), hasLength(4));
    });

    test('an unsalted hash is not equal to any salted one', () {
      final unsalted = HashUtils.transactionDedupHash(
        date: date,
        amount: -1200,
        description: 'Rent',
      );
      expect(
        unsalted,
        isNot(
          HashUtils.transactionDedupHash(
            date: date,
            amount: -1200,
            description: 'Rent',
            salt: 'wallet_1',
          ),
        ),
      );
    });
  });

  group('the hash is stable', () {
    test('same inputs, same hash, across calls', () {
      // It is persisted, so it has to survive a relaunch — nothing in the
      // input may vary per process.
      final a = HashUtils.transactionDedupHash(
        date: date,
        amount: -10,
        description: 'X',
        salt: 's',
      );
      final b = HashUtils.transactionDedupHash(
        date: date,
        amount: -10,
        description: 'X',
        salt: 's',
      );
      expect(a, b);
      expect(a, hasLength(64)); // SHA-256 hex
    });

    test('the time of day is part of the identity', () {
      // Worth pinning: an import that stamped `DateTime.now()` instead of the
      // statement date would never dedupe on re-import.
      expect(
        HashUtils.transactionDedupHash(
          date: DateTime(2026, 3, 15),
          amount: -10,
          description: 'X',
        ),
        isNot(
          HashUtils.transactionDedupHash(
            date: DateTime(2026, 3, 15, 12),
            amount: -10,
            description: 'X',
          ),
        ),
      );
    });
  });

  // Everything above pins the salt table against itself: each salt is typed
  // out by hand, so a caller that changed its salt would pass untouched. These
  // run the real call sites and check what they stored. (The xpub sync's call
  // site is exercised in xpub_service_test.dart; a manual entry's hash is
  // built inline in the add sheet from the clock, which is the point of it.)
  group('the call sites use the salts above', () {
    late AppDatabase db;
    late int walletId;

    setUp(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      db = AppDatabase.forTesting(NativeDatabase.memory());
      walletId = (await db.select(db.wallets).getSingle()).id;
    });
    tearDown(() => db.close());

    test(
      'statement import hashes the signed amount with the source salt',
      () async {
        final service = ImportService(db, OllamaService(db));
        final prices = BtcPriceService(db);
        final day = DateTime(2025, 3, 4);
        await db
            .into(db.btcPriceHistory)
            .insert(
              BtcPriceHistoryCompanion.insert(
                date: '2025-03-04',
                currency: prices.currency,
                price: 80000,
              ),
            );
        final source = await service.createSource(
          name: 'Card',
          type: 'bank',
          currency: 'USD',
        );

        await service.saveTransactions(
          transactions: [
            ParsedTransaction(
              date: day,
              amount: 49.99,
              direction: 'debit',
              description: 'Amazon',
              rawDescription: 'AMAZON MKTPLACE',
              currency: 'USD',
            ),
          ],
          sourceId: source,
          sourceName: 'Card',
          btcPriceService: prices,
        );

        final row = await db.select(db.transactions).getSingle();
        expect(
          row.dedupHash,
          HashUtils.transactionDedupHash(
            date: day,
            amount: -49.99,
            description: 'AMAZON MKTPLACE',
            salt: 'source_$source',
          ),
        );
      },
    );

    group('recurring series', () {
      Future<void> seed(String description, DateTime anchor, String hash) => db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: walletId,
              date: anchor,
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

      test('a generated row carries the series-and-due-date salt', () async {
        final anchor = DateTime(2026, 1, 15);
        await seed('Rent', anchor, 'seed');
        await TransactionService(
          db,
        ).generateDueRecurring(now: DateTime(2026, 2, 20));

        final feb =
            await (db.select(db.transactions)
              ..where((t) => t.date.equals(DateTime(2026, 2, 15)))).getSingle();
        expect(feb.recurringSeriesId, isNotNull);
        expect(
          feb.dedupHash,
          TransactionService.recurringDedupHash(
            feb.recurringSeriesId!,
            DateTime(2026, 2, 15),
          ),
        );
      });

      test('two series started the same day both generate', () async {
        // The collision that actually bit: the date picker returns midnight,
        // so two series started on one day had identical anchors, and one of
        // them never generated.
        final anchor = DateTime(2026, 1, 15);
        await seed('Rent', anchor, 'seed-rent');
        await seed('Car loan', anchor, 'seed-car');
        await TransactionService(
          db,
        ).generateDueRecurring(now: DateTime(2026, 3, 20));

        final rows = await db.select(db.transactions).get();
        expect(rows.where((t) => t.description == 'Rent'), hasLength(3));
        expect(rows.where((t) => t.description == 'Car loan'), hasLength(3));
      });
    });
  });
}
