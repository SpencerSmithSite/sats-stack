/// Paths the third review found with no test at all: the xpub money maths
/// beyond a single receive, budget alert thresholds, the one-time move of the
/// Maple key out of the database, and export followed by import.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/budget_service.dart';
import 'package:sats_stack/core/services/notification_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/core/services/xpub_service.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';

// BIP84 test vector, account m/84'/0'/0'.
const _zpub =
    'zpub6rFR7y4Q2AijBEqTUquhVz398htDFrtymD9xYYfG1m4wAcvPhXNfE3EfH1r1ADqtf'
    'SdVCToUG868RvUUkgDKf31mGDtKsAYz2oz2AGutZYs';
const _outsider = 'bc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh';

class _Prices extends BtcPriceService {
  _Prices(super.db);
  @override
  Future<double?> getHistoricalPrice(DateTime date, String currency) async =>
      100000;
}

class _Keys extends SecureKeyStore {
  _Keys();
  final stored = <String, String>{};
  @override
  Future<String> read(String providerId) async => stored[providerId] ?? '';
  @override
  Future<bool> write(String providerId, String value) async {
    stored[providerId] = value;
    return true;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('xpub money maths', () {
    test(
      'a receive, a spend with change, a self-send and a split receive',
      () async {
        final keys = XpubService(db);
        final r0 = keys.deriveAddresses(_zpub, 0, 1).single;
        final r1 = keys.deriveAddresses(_zpub, 1, 1).single;
        final c0 = keys.deriveAddresses(_zpub, 0, 1, chain: 1).single;

        int t(int day) =>
            DateTime.utc(2025, 3, day, 12).millisecondsSinceEpoch ~/ 1000;
        Map<String, dynamic> tx(
          String id,
          int day,
          List<(String, int)> ins,
          List<(String, int)> outs,
        ) => {
          'txid': id * 16,
          'status': {'confirmed': true, 'block_time': t(day)},
          'vin': [
            for (final (a, v) in ins)
              {
                'prevout': {'scriptpubkey_address': a, 'value': v},
              },
          ],
          'vout': [
            for (final (a, v) in outs) {'scriptpubkey_address': a, 'value': v},
          ],
        };

        final receive = tx('aaaa', 1, [(_outsider, 200000)], [(r0, 100000)]);
        // 100,000 in; 60,000 out to someone else, 39,000 back as change, fee
        // 1,000. The wallet is down 61,000, not 100,000.
        final spend = tx(
          'bbbb',
          2,
          [(r0, 100000)],
          [(_outsider, 60000), (c0, 39000)],
        );
        // Change moved to the wallet's own receive address: only the fee left.
        final selfSend = tx('cccc', 3, [(c0, 39000)], [(r1, 38500)]);
        // One payment to two of the wallet's addresses is one row.
        final split = tx(
          'dddd',
          4,
          [(_outsider, 9000)],
          [(r0, 2000), (r1, 1000)],
        );
        final history = <String, List<Map<String, dynamic>>>{
          r0: [receive, spend, split],
          r1: [selfSend, split],
          c0: [spend, selfSend],
        };

        final sync = XpubService(
          db,
          client: MockClient((req) async {
            for (final MapEntry(key: a, value: txs) in history.entries) {
              if (req.url.path.endsWith('/address/$a/txs')) {
                return http.Response(jsonEncode(txs), 200);
              }
            }
            return http.Response('[]', 200);
          }),
        );
        final id = await db
            .into(db.wallets)
            .insert(
              WalletsCompanion.insert(
                label: 'Cold',
                type: 'xpub',
                xpub: const Value(_zpub),
                color: '#F7931A',
              ),
            );
        final wallet =
            await (db.select(db.wallets)
              ..where((w) => w.id.equals(id))).getSingle();

        final result = await sync.syncWallet(
          wallet: wallet,
          btcPriceService: _Prices(db),
        );

        final rows =
            await (db.select(db.transactions)
              ..orderBy([(r) => OrderingTerm.asc(r.date)])).get();
        expect(result.imported, 4);
        expect(rows.map((r) => r.amountSats), [100000, -61000, -500, 3000]);
        expect(rows.fold<int>(0, (s, r) => s + r.amountSats), 41500);
        // Priced at 100,000 a coin.
        expect(rows[1].amountFiat, closeTo(-61, 1e-9));
      },
    );
  });

  group('budget alert thresholds', () {
    Future<List<String>> alertsAt(double spent) async {
      final food =
          (await (db.select(db.categories)
                ..where((c) => c.name.equals('Food & Dining'))).getSingle())
              .id;
      final wallet = (await db.select(db.wallets).getSingle()).id;
      final budgets = BudgetService(db);
      await budgets.upsert(categoryId: food, amountFiat: 100, currency: 'USD');
      await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: wallet,
              date: DateTime(2026, 3, 10),
              description: 'Groceries',
              amountSats: 0,
              amountFiat: -spent,
              fiatCurrency: 'USD',
              category: const Value('Food & Dining'),
              source: 'manual',
              dedupHash: 'g$spent',
            ),
          );
      final claimed = <String>[];
      await budgets.checkAndNotify(
        notifications: NotificationService(
          claim: (k) async {
            claimed.add(k.split('_').take(2).join('_'));
            return true;
          },
        ),
        currency: 'USD',
        now: DateTime(2026, 3, 20),
      );
      return claimed;
    }

    test('79% is quiet', () async => expect(await alertsAt(79), isEmpty));
    test('80% warns', () async => expect(await alertsAt(80), ['budget_warn']));
    test(
      'exactly 100% warns but is not over',
      () async => expect(await alertsAt(100), ['budget_warn']),
    );
    test(
      'over 100% is an overspend, not also a warning',
      () async => expect(await alertsAt(100.01), ['budget_over']),
    );
  });

  test('a Maple key left in the database moves to the keychain', () async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: AppConstants.settingMapleApiKey,
            value: 'maple-secret',
          ),
        );
    final keys = _Keys();

    final ollama = OllamaService(db, keyStore: keys);
    await ollama.loadSettings();

    expect(keys.stored['maple'], 'maple-secret');
    expect(ollama.mapleApiKey, 'maple-secret');
    final left =
        await (db.select(db.appSettings)..where(
          (s) => s.key.equals(AppConstants.settingMapleApiKey),
        )).getSingleOrNull();
    expect(left, isNull, reason: 'the plaintext copy must be gone');
  });

  test('an export, imported again, is the same data', () async {
    final dir = await Directory.systemTemp.createTemp('export');
    addTearDown(() => dir.delete(recursive: true));
    final wallet = (await db.select(db.wallets).getSingle()).id;
    await db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: wallet,
            date: DateTime(2026, 3, 1),
            description: 'Rent',
            amountSats: -1000000,
            amountFiat: -1200,
            fiatCurrency: 'GBP',
            source: 'manual',
            dedupHash: 'rent',
          ),
        );

    final backup = '${dir.path}/backup.sqlite';
    File(backup).writeAsStringSync('what the save dialog left'); // replaced
    await exportDatabaseTo(db, backup);

    final live = File('${dir.path}/live.sqlite')..writeAsStringSync('old');
    final r = await replaceDatabaseFile(source: File(backup), target: live);
    expect(r.outcome, RestoreOutcome.replaced);

    final restored = AppDatabase.forTesting(NativeDatabase(live));
    addTearDown(restored.close);
    final rows = await restored.select(restored.transactions).get();
    expect(rows.map((t) => (t.description, t.amountFiat, t.fiatCurrency)), [
      ('Rent', -1200.0, 'GBP'),
    ]);
  });
}
