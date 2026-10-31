/// Rows already imported from a source are recognised before the preview,
/// even when an AI tier described them in its own words (audit A-1).
///
/// The save step's hash includes the description. On the AI tiers that is the
/// model's wording, which changes between runs and never matches the rules
/// tier's bank text, so re-importing an overlapping statement — or the same
/// file through a different tier — wrote every overlapping row a second time.
library;

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/main.dart' as app;
import 'package:sats_stack/screens/import/import_preview_screen.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  final march4 = DateTime(2025, 3, 4);
  final march5 = DateTime(2025, 3, 5);

  ParsedTransaction row(
    DateTime date,
    double amount,
    String description, {
    String direction = 'debit',
  }) => ParsedTransaction(
    date: date,
    amount: amount,
    direction: direction,
    description: description,
    rawDescription: description,
    currency: 'USD',
  );

  late AppDatabase db;
  late ImportService service;
  late BtcPriceService prices;
  late int source;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    service = ImportService(db, OllamaService(db));
    prices = BtcPriceService(db);
    for (final day in ['2025-03-04', '2025-03-05']) {
      await db
          .into(db.btcPriceHistory)
          .insert(
            BtcPriceHistoryCompanion.insert(
              date: day,
              currency: prices.currency,
              price: 80000,
            ),
          );
    }
    source = await service.createSource(
      name: 'Card',
      type: 'bank',
      currency: 'USD',
    );
  });

  tearDown(() => db.close());

  Future<void> save(List<ParsedTransaction> rows) => service.saveTransactions(
    transactions: rows,
    sourceId: source,
    sourceName: 'Card',
    btcPriceService: prices,
  );

  Future<int> ledgerRows() async =>
      (await db.select(db.transactions).get()).length;

  test('an AI re-read of an imported statement adds nothing', () async {
    // First import: the rules tier, bank text.
    await save([
      row(march4, 4.5, 'STARBUCKS #1234 SEATTLE WA'),
      row(march5, 1200, 'RENT PAYMENT REF 88213'),
    ]);
    expect(await ledgerRows(), 2);

    // The same statement read by an AI tier: same rows, the model's words.
    final again = [
      row(march4, 4.5, 'Starbucks coffee'),
      row(march5, 1200, 'Rent'),
    ];
    expect(await service.markLikelyDuplicates(again, source), 2);
    expect(again.every((t) => t.likelyDuplicate && !t.include), isTrue);

    await save(again);
    expect(await ledgerRows(), 2);
  });

  test('an overlapping statement brings only its new rows', () async {
    await save([
      row(march4, 4.5, 'Starbucks'),
      row(march4, 4.5, 'Starbucks'), // two coffees, same day
    ]);
    final next = [
      row(march4, 4.5, 'Coffee shop'),
      row(march4, 4.5, 'Coffee shop'),
      row(march4, 4.5, 'Bakery'), // a third the first file did not have
      row(march5, 9.99, 'Streaming'),
    ];
    expect(await service.markLikelyDuplicates(next, source), 2);
    expect(next.map((t) => t.include), [false, false, true, true]);

    await save(next);
    expect(await ledgerRows(), 4);
  });

  test('an exact description is matched before a reworded one', () async {
    await save([row(march4, 10, 'UBER TRIP')]);
    final next = [row(march4, 10, 'LYFT RIDE'), row(march4, 10, 'UBER TRIP')];
    expect(await service.markLikelyDuplicates(next, source), 1);
    // The new ride stays in; the one already stored is the one flagged.
    expect(next.map((t) => t.likelyDuplicate), [false, true]);
  });

  test('direction and amount must match too', () async {
    await save([row(march4, 25, 'Shop')]);
    final next = [
      row(march4, 25, 'Shop', direction: 'credit'), // a refund
      row(march4, 25.01, 'Shop'),
    ];
    expect(await service.markLikelyDuplicates(next, source), 0);
  });

  test('another source is not looked at', () async {
    await save([row(march4, 4.5, 'Starbucks')]);
    final other = await service.createSource(
      name: 'Other card',
      type: 'bank',
      currency: 'USD',
    );
    final next = [row(march4, 4.5, 'Starbucks')];
    expect(await service.markLikelyDuplicates(next, other), 0);
  });

  test('a row the user ticks back in is imported', () async {
    await save([row(march4, 4.5, 'STARBUCKS #1234')]);
    final next = [row(march4, 4.5, 'Bakery')];
    await service.markLikelyDuplicates(next, source);
    next.single.include = true; // "no, this one is new"
    await save(next);
    expect(await ledgerRows(), 2);
  });

  testWidgets('the preview unticks and labels them, and says so', (
    tester,
  ) async {
    await tester.runAsync(() async {
      await save([row(march4, 4.5, 'STARBUCKS #1234')]);
      app.importService = service;
    });
    final result = ImportResult(
      transactions: [
        row(march4, 4.5, 'Starbucks coffee'),
        row(march5, 9.99, 'Streaming'),
      ],
      fileType: ImportFileType.csv,
      fileName: 'statement.csv',
      tierUsed: ImportTier.ollama,
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: ImportPreviewScreen(
          result: result,
          sourceId: source,
          sourceName: 'Card',
        ),
      ),
    );
    for (var i = 0; i < 3; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }

    expect(find.textContaining('Already imported?'), findsOneWidget);
    expect(
      find.textContaining('1 looks already imported, so it is unticked'),
      findsOneWidget,
    );
    expect(find.text('Import 1 transaction'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });
}
