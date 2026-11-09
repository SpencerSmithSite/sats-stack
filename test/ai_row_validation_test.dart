/// The rows an AI returns are read as strictly as a file's own, and the ones
/// it got wrong are counted rather than lost without a word (audit A-14).
///
/// An amount given as text dropped the row; `DateTime.tryParse` turned
/// 2026-02-30 into 2 March and read a `…Z` timestamp as an instant, which
/// local time could move into another month; and a row that did not say
/// which way the money went was booked as spending.
library;

import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/models/ai_provider.dart';
import 'package:sats_stack/core/services/import_service.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

class _NoKeys extends SecureKeyStore {
  const _NoKeys();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// An on-device model, so no consent is asked, that answers with [reply].
class _Model extends OllamaService {
  _Model(super.db, this.reply) : super(keyStore: const _NoKeys());

  final String reply;

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
    yield reply;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late Directory dir;
  late int sourceId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    dir = await Directory.systemTemp.createTemp('ai_rows');
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

  test('rows are read strictly, and the bad ones counted', () async {
    const reply = '''[
      {"date":"2026-03-31T23:30:00Z","amount":4,"direction":"debit","description":"Late"},
      {"date":"2026-03-02","amount":"12.50","direction":"debit","description":"Text amount"},
      {"date":"2026-03-03","amount":"1,234.50","direction":"credit","description":"Grouped"},
      {"date":"2026-03-04","amount":-7,"description":"Signed, no direction"},
      {"date":"2026-03-05","amount":20,"direction":" Credit ","description":"Spaced"},
      {"date":"2026-02-30","amount":1,"direction":"debit","description":"No such day"},
      {"date":"03/04/2026","amount":1,"direction":"debit","description":"Which order"},
      {"date":"2026-03-06","amount":9,"description":"Which way"},
      {"date":"2026-03-07","amount":null,"direction":"debit","description":"No amount"},
      "not a row"
    ]''';
    final file = File('${dir.path}/statement.csv')
      ..writeAsStringSync('Date,Description,Amount\n2026-03-01,Coffee,-3.50\n');
    final result = await ImportService(db, _Model(db, reply)).importFile(
      filePath: file.path,
      fileName: 'statement.csv',
      sourceId: sourceId,
    );

    expect(result.tierUsed, ImportTier.ollama);
    final byName = {for (final t in result.transactions) t.description: t};
    expect(byName.keys, {
      'Late',
      'Text amount',
      'Grouped',
      'Signed, no direction',
      'Spaced',
    });
    // The day the model wrote, whatever the device's timezone.
    expect(byName['Late']!.date, DateTime(2026, 3, 31));
    expect(byName['Text amount']!.amount, 12.5);
    expect(byName['Grouped']!.amount, 1234.5);
    expect(byName['Grouped']!.direction, 'credit');
    expect(byName['Signed, no direction']!.direction, 'debit');
    expect(byName['Signed, no direction']!.amount, 7);
    expect(byName['Spaced']!.direction, 'credit');
    expect(result.aiRowsDropped, 5);
  });

  test('a clean answer drops nothing', () async {
    const reply =
        '[{"date":"2026-03-01","amount":3.5,"direction":"debit",'
        '"description":"Coffee","currency":"GBP"}]';
    final file = File('${dir.path}/statement.csv')
      ..writeAsStringSync('Date,Description,Amount\n2026-03-01,Coffee,-3.50\n');
    final result = await ImportService(db, _Model(db, reply)).importFile(
      filePath: file.path,
      fileName: 'statement.csv',
      sourceId: sourceId,
    );
    expect(result.transactions, hasLength(1));
    expect(result.aiRowsDropped, 0);
  });
}
