/// Pricing an import in bulk, and the import flow's smaller misreadings.
///
/// Historical prices were fetched one day at a time, at most once a second,
/// with nothing on screen: a year of statement took five minutes behind a
/// spinner. Amounts with a currency code or a narrow no-break space did not
/// parse, a model's per-row currency was taken on trust, and "Other…"
/// currency could not be chosen.
library;

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/screens/import/import_source_setup_screen.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A private backend that answers every request with [reply].
class _Model extends OllamaService {
  _Model(super.db, this.reply) : super(keyStore: const _NoKeyStore());
  final String reply;
  @override
  AiProvider get activeProvider => AiProvider.appleIntelligence;
  @override
  bool get sendsDataOffDevice => false;
  @override
  Future<bool> isAvailable() async => true;
  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    yield reply;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  group('bulk pricing', () {
    final days = [for (var d = 1; d <= 10; d++) DateTime(2025, 3, d)];
    int ts(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

    /// A price history: one point per day at the moment a one-day request
    /// asks for, priced 80,000 + the day of the month.
    String series() => jsonEncode({
      'prices': [
        for (final d in days.reversed) {'time': ts(d), 'GBP': 80000 + d.day},
      ],
      'exchangeRates': const {},
    });

    test('many days are priced from one request', () async {
      final requests = <Uri>[];
      final prices = BtcPriceService(
        db,
        clock: () => DateTime(2026, 1, 1),
        client: MockClient((req) async {
          requests.add(req.url);
          return http.Response(series(), 200);
        }),
      );

      expect(await prices.prefetchHistoricalPrices(days, 'gbp'), 10);
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters, {'currency': 'GBP'});
      for (final d in days) {
        expect(await prices.getHistoricalPrice(d, 'GBP'), 80000 + d.day);
      }
      expect(requests, hasLength(1), reason: 'every day was a cache hit');
    });

    test('a few days are left to the one-day lookups', () async {
      var requests = 0;
      final prices = BtcPriceService(
        db,
        clock: () => DateTime(2026, 1, 1),
        client: MockClient((_) async {
          requests++;
          return http.Response(series(), 200);
        }),
      );
      expect(await prices.prefetchHistoricalPrices(days.take(3), 'GBP'), 0);
      expect(requests, 0);
    });

    test('a server without the endpoint costs nothing but the try', () async {
      final prices = BtcPriceService(
        db,
        clock: () => DateTime(2026, 1, 1),
        client: MockClient((_) async => http.Response('not found', 404)),
      );
      expect(await prices.prefetchHistoricalPrices(days, 'GBP'), 0);
    });

    test('saving an import reports its pricing progress', () async {
      final prices = BtcPriceService(
        db,
        clock: () => DateTime(2026, 1, 1),
        client: MockClient((_) async => http.Response(series(), 200)),
      );
      final service = ImportService(db, OllamaService(db));
      final source = await service.createSource(
        name: 'Card',
        type: 'bank',
        currency: 'GBP',
      );
      final progress = <(int, int)>[];
      await service.saveTransactions(
        transactions: [
          for (final d in days)
            ParsedTransaction(
              date: d,
              amount: 10,
              direction: 'debit',
              description: 'Shop ${d.day}',
              rawDescription: 'Shop ${d.day}',
              currency: 'GBP',
            ),
        ],
        sourceId: source,
        sourceName: 'Card',
        btcPriceService: prices,
        onPricingProgress: (done, total) => progress.add((done, total)),
      );
      expect(progress.first, (0, 10));
      expect(progress.last, (9, 10));
    });
  });

  group('amounts', () {
    Future<List<double>> amounts(String column) async {
      final rows = await ImportService(
        db,
        OllamaService(db),
      ).parseWithRules('Date,Description,Amount\n$column', currency: 'EUR');
      return [
        for (final r in rows!) r.direction == 'debit' ? -r.amount : r.amount,
      ];
    }

    test('with an ISO code before or after', () async {
      expect(await amounts('2026-03-01,A,"GBP -12.50"\n'), [-12.5]);
      expect(await amounts('2026-03-01,A,"-12,50 EUR"\n'), [-12.5]);
    });

    test('grouped with a narrow no-break space or an apostrophe', () async {
      expect(await amounts('2026-03-01,A,"-1 234,56"\n'), [-1234.56]);
      expect(await amounts("2026-03-01,A,-1'234.50\n"), [-1234.5]);
    });
  });

  group("a model's per-row currency", () {
    Future<String> currencyOf(String reply, String csv) async {
      final dir = await Directory.systemTemp.createTemp('rowcur');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/s.csv')..writeAsStringSync(csv);
      final service = ImportService(db, _Model(db, reply));
      final source = await service.createSource(
        name: 'Card',
        type: 'bank',
        currency: 'GBP',
      );
      final result = await service.importFile(
        filePath: file.path,
        fileName: 's.csv',
        sourceId: source,
      );
      return result.transactions.single.currency;
    }

    String reply(String currency) =>
        '[{"date":"2026-03-01","amount":3.5,"direction":"debit",'
        '"description":"Coffee","currency":"$currency"}]';

    test('is ignored when the file never names it', () async {
      expect(
        await currencyOf(
          reply('USD'),
          'Date,Description,Amount\n2026-03-01,Coffee,-3.50\n',
        ),
        'GBP',
      );
    });

    test('is kept when the file names it', () async {
      expect(
        await currencyOf(
          reply('EUR'),
          'Date,Description,Amount,Currency\n2026-03-01,Coffee,-3.50,EUR\n',
        ),
        'EUR',
      );
    });

    test('is ignored when it is not a code at all', () async {
      expect(
        await currencyOf(
          reply('dollars'),
          'Date,Description,Amount\n2026-03-01,Coffee,-3.50\n',
        ),
        'GBP',
      );
    });
  });

  testWidgets('"Other…" currency opens a code field', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ImportSourceSetupScreen()));
    expect(find.text('Custom Currency Code'), findsNothing);

    await tester.tap(find.text('USD'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other…').last);
    await tester.pumpAndSettle();

    expect(find.text('Custom Currency Code'), findsOneWidget);
  });
}
