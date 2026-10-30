/// Tests for the statement categoriser.
///
/// The cases here are the real misclassifications the audit found, every one of
/// which came from matching keywords with a bare `contains` and returning the
/// first hit. Getting these wrong is not cosmetic: the category drives the
/// budget a transaction counts against and the dashboard's spending breakdown.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late ImportService service;
  late BtcPriceService prices;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // Prices answered from memory: these tests are about categories, and they
    // used to reach live price endpoints on every save.
    prices = BtcPriceService(
      db,
      client: MockClient((_) async => http.Response('', 404)),
    );
    service = ImportService(db, OllamaService(db));
  });

  tearDown(() => db.close());

  group('keywords match whole words only', () {
    test('a keyword inside a longer word does not match', () {
      // 'sport' in PASSPORT, 'shop' in BARBERSHOP, 'bar' in BARBERSHOP.
      expect(service.matchCategory('PASSPORT OFFICE'), isNull);
      expect(service.matchCategory('BARBERSHOP'), isNull);
      // 'rent' in CURRENT, 'gas' in LAS VEGAS.
      expect(service.matchCategory('CURRENT ACCOUNT FEE'), isNull);
    });

    test('the same keyword as a word still matches', () {
      expect(service.matchCategory('SPORT DIRECT'), 'Entertainment');
      expect(service.matchCategory('THE BIKE SHOP'), 'Shopping');
      expect(service.matchCategory('RENT APRIL'), 'Housing');
    });

    test('keywords ending in punctuation match', () {
      // `\b` asserts the wrong thing after '+' and '&'.
      expect(service.matchCategory('DISNEY+ MONTHLY'), 'Subscriptions');
      expect(service.matchCategory('AT&T WIRELESS'), 'Housing');
      expect(service.matchCategory('CHICK-FIL-A 1234'), 'Food & Dining');
    });
  });

  group('the longest match wins, not the first', () {
    test('a specific phrase beats a shorter keyword in another category', () {
      // 'monthly fee' (Subscriptions) vs 'refund' (Income).
      expect(service.matchCategory('MONTHLY FEE REFUND'), 'Subscriptions');
      // 'rent a car' (Transport) vs 'rent' (Housing).
      expect(service.matchCategory('RENT A CAR HERTZ'), 'Transport');
      // 'trader joe' (Food) vs 'refund' (Income).
      expect(service.matchCategory('TRADER JOE REFUND'), 'Food & Dining');
      // 'electric' (Housing) vs 'shell' (Transport).
      expect(service.matchCategory('SHELL ENERGY ELECTRIC'), 'Housing');
    });

    test('ordinary merchants still land where they should', () {
      expect(service.matchCategory('STARBUCKS STORE 442'), 'Food & Dining');
      expect(service.matchCategory('UBER TRIP'), 'Transport');
      expect(service.matchCategory('NETFLIX.COM'), 'Subscriptions');
      expect(service.matchCategory('PAYROLL ACME LTD'), 'Income');
      expect(service.matchCategory('COINBASE BUY'), 'Bitcoin');
      expect(service.matchCategory('AMAZON MKTPLACE'), 'Shopping');
    });

    test('nothing recognisable returns null, not Other', () {
      // The caller applies the fallback and records that it did, which is what
      // keeps it out of the learned mappings.
      expect(service.matchCategory('ZZQX TRANSFER 99812'), isNull);
    });
  });

  group('a guessed category is not learned', () {
    Future<int> newSource() => db
        .into(db.importSources)
        .insert(
          ImportSourcesCompanion.insert(
            name: 'Barclays',
            type: 'bank',
            currency: 'GBP',
          ),
        );

    test('the fallback is never written as a mapping', () async {
      final sourceId = await newSource();
      final rows = [
        ParsedTransaction(
          date: DateTime(2026, 3, 1),
          amount: 12.5,
          direction: 'debit',
          description: 'ZZQX TRANSFER 99812',
          rawDescription: 'ZZQX TRANSFER 99812',
          currency: 'GBP',
          category: 'Other',
          categoryIsFallback: true,
        ),
      ];

      await service.saveTransactions(
        transactions: rows,
        sourceId: sourceId,
        sourceName: 'Barclays',
        btcPriceService: prices,
      );

      // Learning this would pin the merchant to Other on every future import
      // of this source, whatever the keyword list later says.
      expect(await db.select(db.descriptionCategoryMappings).get(), isEmpty);
    });

    test('a category the user chose is learned', () async {
      final sourceId = await newSource();
      final row = ParsedTransaction(
        date: DateTime(2026, 3, 1),
        amount: 12.5,
        direction: 'debit',
        description: 'ZZQX TRANSFER 99812',
        rawDescription: 'ZZQX TRANSFER 99812',
        currency: 'GBP',
        category: 'Other',
        categoryIsFallback: true,
      );
      // What the edit sheet does.
      row.setUserCategory('Housing');

      await service.saveTransactions(
        transactions: [row],
        sourceId: sourceId,
        sourceName: 'Barclays',
        btcPriceService: prices,
      );

      final mappings = await db.select(db.descriptionCategoryMappings).get();
      expect(mappings, hasLength(1));
      expect(mappings.single.category, 'Housing');
      expect(mappings.single.description, 'zzqx transfer 99812');
    });
  });

  group('specificity beats raw length', () {
    test('a transport ticket is not entertainment', () {
      // 'ticket' is six characters, so under a pure longest-match rule it
      // outscored 'train' (5), 'bus' (3) and 'metro' (5).
      expect(service.matchCategory('TRAIN TICKET'), 'Transport');
      expect(service.matchCategory('BUS TICKET LONDON'), 'Transport');
      expect(service.matchCategory('METRO TICKET'), 'Transport');
    });

    test('actual ticket vendors are still entertainment', () {
      expect(service.matchCategory('TICKETMASTER UK'), 'Entertainment');
      expect(service.matchCategory('EVENTBRITE'), 'Entertainment');
      expect(service.matchCategory('ODEON CINEMA'), 'Entertainment');
    });
  });

  group('only a user-chosen category is learned', () {
    test('a keyword guess is not persisted as a mapping', () async {
      final sourceId = await db
          .into(db.importSources)
          .insert(
            ImportSourcesCompanion.insert(
              name: 'Barclays',
              type: 'bank',
              currency: 'GBP',
            ),
          );

      // A confident keyword match, not the fallback — previously learned,
      // which froze a wrong guess into the source for good.
      final row = ParsedTransaction(
        date: DateTime(2026, 3, 1),
        amount: 12.5,
        direction: 'debit',
        description: 'TRAIN TICKET',
        rawDescription: 'TRAIN TICKET',
        currency: 'GBP',
        category: 'Transport',
      );

      await service.saveTransactions(
        transactions: [row],
        sourceId: sourceId,
        sourceName: 'Barclays',
        btcPriceService: prices,
      );

      expect(await db.select(db.descriptionCategoryMappings).get(), isEmpty);
    });
  });
}
