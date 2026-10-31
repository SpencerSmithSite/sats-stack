/// An AI import is sent in parts each backend can read and answer whole, and
/// an answer cut off partway keeps what it returned (audit A-2, A-3).
///
/// The whole file — up to 100,000 characters — went in one request. The
/// on-device models (about 4,000 characters of context) overflowed and failed
/// silently; Ollama truncated the prompt itself; and a hosted provider's
/// answer, capped at 4,096 tokens, stopped after about 90 rows, failed to
/// parse, and fell back — after the statement had been uploaded.
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

/// Answers each part with one JSON row per CSV row it was sent, unless
/// [cutOffAfter] says to stop partway through the answer.
class _Model extends OllamaService {
  _Model(super.db, {this.budget = 24000, this.cutOffAfter})
    : super(keyStore: const _NoKeys());

  final int budget;
  final int? cutOffAfter;
  final prompts = <String>[];

  @override
  AiProvider get activeProvider => AiProvider.claude;
  @override
  int get contextBudgetChars => budget;
  @override
  String? get selectedModel => 'test';

  @override
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
    final prompt = messages.last['content']!;
    prompts.add(prompt);
    final rows = [
      for (final line in prompt.split('\n'))
        if (RegExp(r'^2026-03-\d\d,').hasMatch(line))
          {
            'date': line.split(',')[0],
            'amount': double.parse(line.split(',')[2]),
            'direction': 'debit',
            'description': line.split(',')[1],
            'currency': 'GBP',
          },
    ];
    var answer = jsonEncode(rows);
    if (cutOffAfter case final n?) {
      answer = answer.substring(0, n);
    }
    yield answer;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  String csv(int rows) => [
    'Date,Payee,Amount',
    for (var i = 0; i < rows; i++)
      '2026-03-${(i % 28 + 1).toString().padLeft(2, '0')},Shop $i,${i + 1}.50',
  ].join('\n');

  group('splitting', () {
    test('parts hold at most 60 rows and each starts with the header', () {
      final parts = ImportService.aiChunks(
        csv(150),
        header: true,
        maxChars: 100000,
      );
      expect(parts, hasLength(3));
      for (final p in parts) {
        final lines = p.split('\n');
        expect(lines.first, 'Date,Payee,Amount');
        expect(lines.length - 1, lessThanOrEqualTo(60));
      }
      final rows = parts.expand((p) => p.split('\n').skip(1)).toList();
      expect(rows, hasLength(150));
      expect(rows.toSet(), hasLength(150));
    });

    test('a small context makes smaller parts', () {
      final parts = ImportService.aiChunks(
        csv(150),
        header: true,
        maxChars: 600,
      );
      expect(parts.every((p) => p.length <= 600), isTrue);
      expect(parts.expand((p) => p.split('\n').skip(1)), hasLength(150));
    });

    test('a PDF has no header to repeat, and blank lines go', () {
      final parts = ImportService.aiChunks(
        'line one\n\nline two\n',
        header: false,
        maxChars: 1000,
      );
      expect(parts, ['line one\nline two']);
    });
  });

  group('a cut-off answer', () {
    test('keeps the objects that arrived', () {
      expect(ImportService.recoverCutOffArray('[{"a":1},{"a":2},{"a":'), [
        {'a': 1},
        {'a': 2},
      ]);
      expect(ImportService.recoverCutOffArray('Sure! [{"a":1}, {"a"'), [
        {'a': 1},
      ]);
    });

    test('with nothing complete, gives up', () {
      expect(ImportService.recoverCutOffArray('[{"a":'), isNull);
      expect(ImportService.recoverCutOffArray('no json here'), isNull);
    });
  });

  group('parsing', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    test('a 150-row statement comes back whole, in three requests', () async {
      final model = _Model(db);
      final service = ImportService(db, model);
      final rows = await service.parseWithOllama(
        csv(150),
        fallbackCurrency: 'GBP',
        header: true,
      );
      expect(model.prompts, hasLength(3));
      expect(rows, hasLength(150));
      expect(model.prompts[1], contains('Part 2 of 3'));
      expect(model.prompts[1], contains('Date,Payee,Amount'));
    });

    test('an on-device context gets small parts', () async {
      final model = _Model(db, budget: 4000);
      final service = ImportService(db, model);
      final rows = await service.parseWithOllama(
        csv(150),
        fallbackCurrency: 'GBP',
        header: true,
      );
      expect(rows, hasLength(150));
      expect(model.prompts.every((p) => p.length <= 4000), isTrue);
    });

    test('a cut-off answer keeps its rows', () async {
      final model = _Model(db, cutOffAfter: 400);
      final service = ImportService(db, model);
      final rows = await service.parseWithOllama(
        csv(10),
        fallbackCurrency: 'GBP',
        header: true,
      );
      expect(rows, isNotNull);
      expect(rows!.length, inInclusiveRange(1, 9));
    });
  });
}
