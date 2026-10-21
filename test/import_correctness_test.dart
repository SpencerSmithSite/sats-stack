/// What a statement import books: which rows survive, which way the money
/// went, and in which currency.
///
/// Every case here was wrong before the 2026-10-21 audit, silently — a
/// dropped row, a charge booked as income, or a dollar figure booked as
/// bitcoin all look like a successful import.
library;

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
  final day = DateTime(2025, 3, 4);

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
    prices = BtcPriceService(db);
    // Cached, so nothing goes to the network.
    for (final (currency, price) in [('USD', 80000.0), ('EUR', 70000.0)]) {
      await db
          .into(db.btcPriceHistory)
          .insert(
            BtcPriceHistoryCompanion.insert(
              date: '2025-03-04',
              currency: currency,
              price: price,
            ),
          );
    }
  });
  tearDown(() => db.close());

  ParsedTransaction row(
    double amount,
    String direction,
    String description, {
    String currency = 'USD',
  }) => ParsedTransaction(
    date: day,
    amount: amount,
    direction: direction,
    description: description,
    rawDescription: description,
    currency: currency,
  );

  Future<ImportSummary> save(List<ParsedTransaction> rows, int source) =>
      service.saveTransactions(
        transactions: rows,
        sourceId: source,
        sourceName: 'x',
        btcPriceService: prices,
      );

  Future<int> source({String currency = 'USD', String type = 'bank'}) =>
      service.createSource(name: type, type: type, currency: currency);

  List<String> directions(List<ParsedTransaction>? rows) => [
    for (final r in rows!) '${r.description}:${r.direction}',
  ];

  group('which rows survive', () {
    test('a refund on the same day as its charge is kept', () async {
      final s = await save([
        row(49.99, 'debit', 'AMAZON MKTPLACE'),
        row(49.99, 'credit', 'AMAZON MKTPLACE'),
      ], await source());
      expect(s.imported, 2);
      final fiat = (await db.select(db.transactions).get()).map(
        (t) => t.amountFiat,
      );
      expect(fiat, unorderedEquals([-49.99, 49.99]));
    });

    test('two identical rows in one file are two transactions', () async {
      final s = await save([
        row(2.80, 'debit', 'TFL TRAVEL CHARGE'),
        row(2.80, 'debit', 'TFL TRAVEL CHARGE'),
      ], await source());
      expect(s.imported, 2);
      expect(await db.select(db.transactions).get(), hasLength(2));
    });

    test('re-importing that file still writes nothing new', () async {
      final id = await source();
      final file = [
        row(2.80, 'debit', 'TFL TRAVEL CHARGE'),
        row(2.80, 'debit', 'TFL TRAVEL CHARGE'),
        row(49.99, 'credit', 'TFL TRAVEL CHARGE'),
      ];
      await save(file, id);
      final again = await save(file, id);
      expect(again.imported, 0);
      expect(again.duplicatesSkipped, 3);
      expect(await db.select(db.transactions).get(), hasLength(3));
    });

    test('the same charge in two accounts is two transactions', () async {
      await save([row(15.99, 'debit', 'NETFLIX.COM')], await source());
      final s = await save([
        row(15.99, 'debit', 'NETFLIX.COM'),
      ], await source(type: 'credit_card'));
      expect(s.imported, 1);
      expect(await db.select(db.transactions).get(), hasLength(2));
    });
  });

  group('which currency', () {
    test('a Swan export into a BTC account is booked in dollars', () async {
      const csv =
          'Date,Type,Amount BTC,Amount USD,Fee USD\n'
          '2025-03-04,purchase,0.00625,500.00,2.50\n';
      final rows = await service.parseWithRules(csv, currency: 'BTC');
      expect(rows!.single.currency, 'USD');
      expect(rows.single.amount, 500);

      await save(rows, await source(currency: 'BTC'));
      final t = await db.select(db.transactions).getSingle();
      // Was -50,000,000,000 sats: 500 read as bitcoin.
      expect(t.isBitcoin, isFalse);
      expect(t.amountFiat, -500);
      expect(t.amountSats, -625000);
    });

    test('a Coinbase row takes its spot-price currency and type', () async {
      const csv =
          'Timestamp,Transaction Type,Asset,Quantity Transacted,'
          'Spot Price Currency,Spot Price at Transaction,Subtotal,'
          'Total (inclusive of fees and/or spread),Fees and/or Spread,Notes\n'
          '2025-03-04T10:00:00Z,Buy,BTC,0.001,EUR,70000,70,71.50,1.50,'
          'Bought BTC\n'
          '2025-03-04T11:00:00Z,Sell,BTC,0.0005,EUR,70000,35,34.40,0.60,'
          'Sold BTC\n';
      final rows = await service.parseWithRules(csv, currency: 'BTC');
      expect([for (final r in rows!) r.currency], ['EUR', 'EUR']);
      expect(directions(rows), ['Bought BTC:debit', 'Sold BTC:credit']);
    });

    test(
      'a EUR account is priced in euros, not the display currency',
      () async {
        await save([
          row(100, 'debit', 'REWE', currency: 'EUR'),
        ], await source(currency: 'EUR'));
        final t = await db.select(db.transactions).getSingle();
        expect(prices.currency, 'USD');
        // €100 at €70,000, not at the $80,000 USD price.
        expect(t.amountSats, -(100 / 70000 * 1e8).round());
      },
    );
  });

  group('which way the money went', () {
    const amexStyle =
        'Date,Description,Amount\n'
        '03/04/2025,STARBUCKS,4.50\n'
        '03/05/2025,WHOLE FOODS,82.10\n'
        '03/06/2025,AUTOPAY PAYMENT - THANK YOU,-500.00\n';

    test('a card that writes charges positive', () async {
      final rows = await service.parseWithRules(
        amexStyle,
        currency: 'USD',
        sourceType: 'credit_card',
      );
      expect(directions(rows), [
        'STARBUCKS:debit',
        'WHOLE FOODS:debit',
        'AUTOPAY PAYMENT - THANK YOU:credit',
      ]);
    });

    test('a bank account: negative is money out, whatever the count', () async {
      final rows = await service.parseWithRules(amexStyle, currency: 'USD');
      expect(directions(rows).last, 'AUTOPAY PAYMENT - THANK YOU:debit');
    });

    test('a UK card statement that marks only credits CR', () async {
      const csv =
          'Date,Description,Amount\n'
          '04/03/2025,TESCO STORES,12.50\n'
          '05/03/2025,PAYMENT RECEIVED,100.00 CR\n'
          '15/03/2025,COSTA COFFEE,3.20\n';
      final rows = await service.parseWithRules(csv, currency: 'GBP');
      expect(directions(rows), [
        'TESCO STORES:debit',
        'PAYMENT RECEIVED:credit',
        'COSTA COFFEE:debit',
      ]);
    });

    test('an unsigned column catches an unmistakable credit', () async {
      const csv =
          'Date,Description,Amount\n'
          '2025-03-01,INTEREST PAID,1.20\n'
          '2025-03-02,GROCERIES,40.00\n';
      final rows = await service.parseWithRules(csv, currency: 'USD');
      expect(directions(rows), ['INTEREST PAID:credit', 'GROCERIES:debit']);
    });

    test('a Wells Fargo export keeps its first row', () async {
      const csv =
          '"03/04/2025","-4.50","*","","STARBUCKS"\n'
          '"03/05/2025","1200.00","*","","PAYROLL ACME"\n';
      final rows = await service.parseWithRules(csv, currency: 'USD');
      expect(directions(rows), ['STARBUCKS:debit', 'PAYROLL ACME:credit']);
    });

    test('a PDF with a running balance reads direction off it', () {
      const text =
          'Date Description Amount Balance\n'
          'Balance brought forward 1,500.00\n'
          '01/03/2025 TESCO STORES 12.50 1,487.50\n'
          '02/03/2025 SALARY ACME LTD 2,000.00 3,487.50\n'
          '03/03/2025 COFFEE SHOP 3.20 3,484.30\n';
      final rows = service.parsePdfText(text, currency: 'GBP');
      expect(directions(rows), [
        'TESCO STORES:debit',
        'SALARY ACME LTD:credit',
        'COFFEE SHOP:debit',
      ]);
    });

    test('a description word does not flip the rest of a PDF', () {
      const text =
          '01/03/2025 TESCO STORES 12.50\n'
          '02/03/2025 CREDIT INTEREST 0.45\n'
          '03/03/2025 SAINSBURYS 20.00\n'
          '04/03/2025 SHELL PETROL 40.00\n';
      final rows = service.parsePdfText(text, currency: 'GBP');
      expect(directions(rows), [
        'TESCO STORES:debit',
        'CREDIT INTEREST:credit',
        'SAINSBURYS:debit',
        'SHELL PETROL:debit',
      ]);
    });
  });
}
