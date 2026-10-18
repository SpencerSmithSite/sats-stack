import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ImportService service;
  late BtcPriceService prices;

  // 2025-03-04, the date every fixture row lands on.
  final txDate = DateTime(2025, 3, 4, 12);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
    prices = BtcPriceService(db);
    // Seeded so getHistoricalPrice is a cache hit and never reaches the network.
    await db.into(db.btcPriceHistory).insert(
          BtcPriceHistoryCompanion.insert(
            date: '2025-03-04',
            currency: 'USD',
            price: 80000,
          ),
        );
  });

  tearDown(() => db.close());

  Future<int> newSource(String currency) => service.createSource(
        name: 'Test $currency',
        type: 'bank',
        currency: currency,
      );

  ParsedTransaction row({
    required double amount,
    required String currency,
    String direction = 'credit',
    String description = 'Deposit',
  }) =>
      ParsedTransaction(
        date: txDate,
        amount: amount,
        direction: direction,
        description: description,
        rawDescription: description,
        currency: currency,
      );

  Future<Transaction> saveOne(ParsedTransaction tx, int sourceId) async {
    await service.saveTransactions(
      transactions: [tx],
      sourceId: sourceId,
      sourceName: 'Test',
      btcPriceService: prices,
    );
    return db.select(db.transactions).getSingle();
  }

  group('a Bitcoin-denominated account', () {
    test('converts BTC to fiat rather than writing BTC into amountFiat',
        () async {
      final sourceId = await newSource('BTC');
      final saved = await saveOne(row(amount: 0.05, currency: 'BTC'), sourceId);

      // The bug: amountFiat held 0.05, which the dashboard summed as money.
      expect(saved.amountSats, 5000000);
      expect(saved.amountFiat, closeTo(4000, 0.01)); // 0.05 BTC @ 80,000
      expect(saved.fiatCurrency, 'USD');
      expect(saved.isBitcoin, isTrue);
    });

    test('converts a SATS account the same way', () async {
      final sourceId = await newSource('SATS');
      final saved =
          await saveOne(row(amount: 5000000, currency: 'SATS'), sourceId);

      expect(saved.amountSats, 5000000);
      expect(saved.amountFiat, closeTo(4000, 0.01));
      expect(saved.isBitcoin, isTrue);
    });

    test('a debit is signed on both columns', () async {
      final sourceId = await newSource('BTC');
      final saved = await saveOne(
        row(amount: 0.05, currency: 'BTC', direction: 'debit'),
        sourceId,
      );

      expect(saved.amountSats, -5000000);
      expect(saved.amountFiat, closeTo(-4000, 0.01));
    });

    test('an unresolvable price leaves fiat at zero, not the BTC figure',
        () async {
      final sourceId = await newSource('BTC');
      // Cached as 0 — the shape a failed lookup leaves behind — so the test
      // exercises the fallback without reaching the network.
      await db.into(db.btcPriceHistory).insert(
            BtcPriceHistoryCompanion.insert(
              date: '2011-07-01',
              currency: 'USD',
              price: 0,
            ),
          );
      final saved = await saveOne(
        ParsedTransaction(
          date: DateTime(2011, 7, 1),
          amount: 0.05,
          direction: 'credit',
          description: 'Deposit',
          rawDescription: 'Deposit',
          currency: 'BTC',
        ),
        sourceId,
      );

      expect(saved.amountSats, 5000000);
      expect(saved.amountFiat, 0.0);
    });
  });

  group("the source's currency", () {
    test('is stored on the row rather than USD', () async {
      final sourceId = await newSource('GBP');
      final saved = await saveOne(row(amount: 40, currency: 'GBP'), sourceId);

      expect(saved.fiatCurrency, 'GBP');
      expect(saved.amountFiat, 40);
    });

    test('reaches every row the rule-based tier parses', () async {
      const csv = 'Date,Description,Amount\n'
          '2025-03-04,Tesco,-40.00\n'
          '2025-03-05,Salary,1200.00\n';

      final parsed = await service.parseWithRules(csv, currency: 'GBP');

      expect(parsed, isNotNull);
      expect(parsed!.map((t) => t.currency), everyElement('GBP'));
    });

    test('reaches every row the manual column mapper parses', () async {
      final sourceId = await newSource('EUR');
      const csv = 'Date,Description,Amount\n2025-03-04,Rewe,-12\n';

      final parsed = await service.parseWithMapping(
        csv,
        ColumnMapping(
          dateColumn: 0,
          descriptionColumn: 1,
          amountColumn: 2,
          dateFormat: 'YYYY-MM-DD',
        ),
        sourceId: sourceId,
      );

      expect(parsed, isNotNull);
      expect(parsed!.single.currency, 'EUR');
    });

    test('a blank or missing code falls back to USD', () async {
      final sourceId = await newSource('   ');
      final parsed = await service.parseWithMapping(
        'Date,Description,Amount\n2025-03-04,Shop,-12\n',
        ColumnMapping(
          dateColumn: 0,
          descriptionColumn: 1,
          amountColumn: 2,
          dateFormat: 'YYYY-MM-DD',
        ),
        sourceId: sourceId,
      );

      expect(parsed!.single.currency, 'USD');
    });
  });

  test('a bulk save commits once, not once per row', () async {
    final sourceId = await newSource('USD');
    final batch = [
      for (var i = 0; i < 25; i++)
        ParsedTransaction(
          date: txDate,
          amount: 10.0 + i,
          direction: 'debit',
          description: 'Row $i',
          rawDescription: 'Row $i',
          currency: 'USD',
        ),
    ];

    var notifications = 0;
    final sub = db.select(db.transactions).watch().listen((_) => notifications++);
    await pumpEventQueue();
    notifications = 0;

    final summary = await service.saveTransactions(
      transactions: batch,
      sourceId: sourceId,
      sourceName: 'Test',
      btcPriceService: prices,
      btcPrice: 80000,
    );
    await pumpEventQueue();
    await sub.cancel();

    expect(summary.imported, 25);
    // One commit, so listeners (main.dart's budget re-check among them) wake
    // once rather than 25 times.
    expect(notifications, 1);
  });
}
