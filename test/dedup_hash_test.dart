/// Pins the deduplication-hash contract.
///
/// `Transactions.dedupHash` is UNIQUE and every insert path uses
/// `InsertMode.insertOrIgnore`, so a hash collision is not an error — it is a
/// silently dropped transaction. Four callers choose four different salts, and
/// each choice means something specific:
///
/// | caller | salt | intent |
/// |---|---|---|
/// | statement import | `wallet_<id>` | re-importing the same file must dedupe |
/// | manual entry | microsecond timestamp | an intentional duplicate must be kept |
/// | recurring series | `recurring_<anchor>_<due>` | one row per due date, idempotent |
/// | xpub sync | `xpub_<txid>`, then `HashUtils.scopedToWallet` | one row per on-chain transaction, per wallet |
///
/// Nothing asserted the distinctions, and getting one wrong is invisible until
/// a user notices a missing row. The audit found exactly that: the import path
/// hashed an unsigned amount, so a charge and its same-day refund collided and
/// the refund vanished.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/shared/utils/hash_utils.dart';

void main() {
  final date = DateTime(2026, 3, 15);

  String importHash({
    required double amount,
    String description = 'AMAZON MKTPLACE',
    int walletId = 1,
    DateTime? on,
  }) => HashUtils.transactionDedupHash(
    date: on ?? date,
    amount: amount,
    description: description,
    salt: 'wallet_$walletId',
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
      // RENT 1500.00 on the 1st, in two different accounts.
      expect(
        importHash(amount: -1500, description: 'RENT', walletId: 1),
        isNot(importHash(amount: -1500, description: 'RENT', walletId: 2)),
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
    String recurring(DateTime anchor, DateTime due) =>
        HashUtils.transactionDedupHash(
          date: due,
          amount: -1200,
          description: 'Rent',
          salt:
              'recurring_${anchor.millisecondsSinceEpoch}'
              '_${due.millisecondsSinceEpoch}',
        );

    final anchor = DateTime(2026, 1, 15);

    test('generating the same due date twice is one row', () {
      // generateDueRecurring runs on every launch; it must be safe to re-run.
      expect(
        recurring(anchor, DateTime(2026, 3, 15)),
        recurring(anchor, DateTime(2026, 3, 15)),
      );
    });

    test('each due date is its own row', () {
      expect(
        recurring(anchor, DateTime(2026, 3, 15)),
        isNot(recurring(anchor, DateTime(2026, 4, 15))),
      );
    });

    test('two series with the same figures stay separate', () {
      // Two monthly £1,200 payments anchored on different dates are two
      // series, not one.
      expect(
        recurring(DateTime(2026, 1, 15), DateTime(2026, 3, 15)),
        isNot(recurring(DateTime(2026, 1, 20), DateTime(2026, 3, 15))),
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
}
