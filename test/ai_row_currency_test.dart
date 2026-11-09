/// A currency the model gives a row is kept only if the file names it, and
/// that check is made once per code for the whole import (audit A-11).
///
/// The check compiled a pattern for every row and ran it over the whole file,
/// so its cost grew with rows times file size. Made once per code, each code
/// must still get its own answer.
library;

import 'dart:convert';

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

/// Answers every part with [rows], whatever it was sent.
class _Model extends OllamaService {
  _Model(super.db, this.rows) : super(keyStore: const _NoKeys());

  final List<Map<String, Object?>> rows;

  @override
  AiProvider get activeProvider => AiProvider.claude;
  @override
  int get contextBudgetChars => 24000;
  @override
  String? get selectedModel => 'test';

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    yield jsonEncode(rows);
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Map<String, Object?> row(String description, String? currency) => {
    'date': '2026-03-02',
    'amount': 12.5,
    'direction': 'debit',
    'description': description,
    'currency': currency,
  };

  test('each claimed code is checked against the file on its own', () async {
    const csv =
        'Date,Payee,Amount\n'
        '2026-03-02,Hotel NYC (USD 40.00),12.50\n'
        '2026-03-02,Cafe,12.50\n'
        '2026-03-02,Bakery,12.50\n'
        '2026-03-02,Kiosk,12.50\n'
        '2026-03-02,Market,12.50\n';
    final model = _Model(db, [
      row('Hotel NYC', 'USD'),
      // Named nowhere in the file: a habit, not a fact.
      row('Cafe', 'EUR'),
      row('Bakery', 'usd'),
      row('Kiosk', 'EUR'),
      row('Market', null),
    ]);
    final rows = await ImportService(
      db,
      model,
    ).parseWithOllama(csv, fallbackCurrency: 'GBP', header: true);

    expect(
      {for (final r in rows!) r.description: r.currency},
      {
        'Hotel NYC': 'USD',
        'Cafe': 'GBP',
        'Bakery': 'USD',
        'Kiosk': 'GBP',
        'Market': 'GBP',
      },
    );
  });
}
