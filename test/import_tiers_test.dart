/// Which tier reads a statement, and what an import remembers.
///
/// On-device AI was never used for an import (it has no model to select, and
/// one was required). A PDF the AI could not read never reached the heuristic
/// reader. A file longer than an AI request was cut without a word. Learned
/// categories were keyed on the description as edited, which no later file
/// contains, and renaming a built-in category sent keyword matches to a name
/// that no longer existed.
library;

import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/painting.dart' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/btc_price_service.dart';
import 'package:sats_stack/core/services/category_service.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// An on-device backend: available, private, and with no model to select.
class _OnDevice extends OllamaService {
  _OnDevice(super.db, {this.reply = _oneRow})
    : super(keyStore: const _NoKeyStore());

  static const _oneRow =
      '[{"date":"2026-03-01","amount":3.5,"direction":"debit",'
      '"description":"Coffee","currency":"GBP"}]';

  final String reply;
  String? lastPrompt;

  @override
  AiProvider get activeProvider => AiProvider.appleIntelligence;
  @override
  bool get sendsDataOffDevice => false;
  @override
  String? get selectedModel => null;
  @override
  Future<bool> isAvailable() async => true;

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    lastPrompt = messages.last['content'];
    yield reply;
  }
}

/// Prices from memory, never the network.
class _Prices extends BtcPriceService {
  _Prices(super.db);
  @override
  Future<double?> getHistoricalPrice(DateTime date, String currency) async =>
      50000;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dir;
  late int sourceId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('tiers');
    sourceId = await db
        .into(db.importSources)
        .insert(
          ImportSourcesCompanion.insert(
            name: 'Card',
            type: 'bank',
            currency: 'GBP',
          ),
        );
  });
  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<ImportResult> importCsv(ImportService service, String csv) {
    final file = File('${dir.path}/statement.csv')..writeAsStringSync(csv);
    return service.importFile(
      filePath: file.path,
      fileName: 'statement.csv',
      sourceId: sourceId,
    );
  }

  test('an on-device backend reads the statement', () async {
    final result = await importCsv(
      ImportService(db, _OnDevice(db)),
      'Date,Description,Amount\n2026-03-01,Coffee,-3.50\n',
    );
    expect(result.tierUsed, ImportTier.ollama);
    expect(result.aiLabel, AiProvider.appleIntelligence.label);
  });

  test('a file cut short for the AI says how much was read', () async {
    final ai = _OnDevice(db);
    final rows = StringBuffer('Date,Description,Amount\n');
    while (rows.length < 120000) {
      rows.write('2026-03-01,Coffee at the corner shop,-3.50\n');
    }
    final result = await importCsv(ImportService(db, ai), rows.toString());

    expect(result.aiInputTruncatedAt, 100000);
    expect(ai.lastPrompt!.length, lessThan(rows.length));
  });

  test('a whole file says nothing about being cut', () async {
    final result = await importCsv(
      ImportService(db, _OnDevice(db)),
      'Date,Description,Amount\n2026-03-01,Coffee,-3.50\n',
    );
    expect(result.aiInputTruncatedAt, isNull);
  });

  test('a PDF the AI cannot read falls back to the heuristic reader', () async {
    final doc = PdfDocument();
    final page = doc.pages.add();
    final font = PdfStandardFont(PdfFontFamily.helvetica, 10);
    const lines = [
      'Statement of account',
      '01/03/2026 Corner Coffee 3.50',
      '02/03/2026 Grocery Mart 42.10',
      '03/03/2026 City Transit 2.80',
      '04/03/2026 Book Shop 12.99',
    ];
    for (var i = 0; i < lines.length; i++) {
      page.graphics.drawString(
        lines[i],
        font,
        bounds: Rect.fromLTWH(0, i * 20.0, 400, 20),
      );
    }
    final file = File('${dir.path}/statement.pdf')
      ..writeAsBytesSync(await doc.save());
    doc.dispose();

    final result = await ImportService(
      db,
      _OnDevice(db, reply: 'Sorry, I cannot read this.'),
    ).importFile(
      filePath: file.path,
      fileName: 'statement.pdf',
      sourceId: sourceId,
    );

    expect(result.tierUsed, ImportTier.pdfHeuristic);
    expect(result.transactions.length, greaterThanOrEqualTo(3));
  });

  test(
    'a learned category follows the description as the file gives it',
    () async {
      final service = ImportService(db, OllamaService(db));
      final first = await importCsv(
        service,
        'Date,Description,Amount\n2026-03-01,SQ *BLUE BOTTLE 1234,-4.00\n',
      );
      final tx =
          first.transactions.single
            ..description = 'Blue Bottle'
            ..setUserCategory('Food & Dining');
      await service.saveTransactions(
        transactions: [tx],
        sourceId: sourceId,
        sourceName: 'Card',
        btcPriceService: _Prices(db),
      );

      final second = await importCsv(
        service,
        'Date,Description,Amount\n2026-04-01,SQ *BLUE BOTTLE 1234,-4.00\n',
      );
      expect(second.transactions.single.category, 'Food & Dining');
    },
  );

  group('a renamed built-in category', () {
    late CategoryService categories;
    late Category food;

    setUp(() async {
      categories = CategoryService(db);
      food =
          await (db.select(db.categories)
            ..where((c) => c.name.equals('Food & Dining'))).getSingle();
    });

    Future<void> rename(String to) => categories.updateCategory(
      id: food.id,
      name: to,
      color: food.color,
      icon: food.icon,
    );

    Future<String?> importedCategory() async =>
        (await importCsv(
          ImportService(db, OllamaService(db)),
          'Date,Description,Amount\n2026-03-01,STARBUCKS 123,-4.00\n',
        )).transactions.single.category;

    test('still receives keyword matches', () async {
      await rename('Food');
      expect(await importedCategory(), 'Food');
    });

    test('renamed twice, under its latest name', () async {
      await rename('Food');
      await rename('Eating out');
      expect(await importedCategory(), 'Eating out');
    });

    test('renamed back, under its own name', () async {
      await rename('Food');
      await rename('Food & Dining');
      expect(await importedCategory(), 'Food & Dining');
      final keys = (await db.select(db.appSettings).get()).map((s) => s.key);
      expect(keys.where((k) => k.startsWith('system_category_name:')), isEmpty);
    });
  });

  test('a saved column layout can be forgotten', () async {
    final service = ImportService(db, OllamaService(db));
    await service.saveColumnMapping(sourceId, ColumnMapping(dateColumn: 0));
    await service.clearColumnMapping(sourceId);
    final source = await db.select(db.importSources).getSingle();
    expect(source.columnMapping, isNull);
  });
}
