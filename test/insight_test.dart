/// The monthly insight: what is cached, and what is not.
library;

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';

class _NoKeyStore extends SecureKeyStore {
  const _NoKeyStore();
  @override
  Future<String> read(String providerId) async => '';
  @override
  Future<bool> write(String providerId, String value) async => true;
}

/// A backend that answers [reply] without the network.
class _Answers extends OllamaService {
  _Answers(super.db, this.reply) : super(keyStore: const _NoKeyStore());
  final String reply;

  @override
  Stream<String> chat(List<Map<String, String>> messages,
      {http.Client? client}) async* {
    if (reply.isNotEmpty) yield reply;
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<String> generate(OllamaService s) => s.generateMonthlyInsight(
        totalStackSats: 1000000,
        btcPrice: 80000,
        monthlyIncome: 4000,
        monthlySpending: 3000,
        monthlySurplus: 1000,
        spendingByCategory: const {'Food & Dining': 600},
      );

  test('an answer is cached as the month insight', () async {
    final s = _Answers(db, 'You saved a quarter of your income.');
    await generate(s);
    expect(await s.loadCachedInsight(), 'You saved a quarter of your income.');
  });

  test('an empty answer is an error, not a cached blank insight', () async {
    final s = _Answers(db, '');
    await expectLater(generate(s), throwsA(isA<InferenceException>()));
    expect(await s.loadCachedInsight(), isNull);
  });
}
