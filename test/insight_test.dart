/// The monthly insight: what is cached, and what is not.
library;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/core/services/inference/inference_backend.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/core/services/secure_key_store.dart';
import 'package:sats_stack/features/dashboard/widgets/ai_insight_card.dart';
import 'package:sats_stack/shared/constants/app_constants.dart';
import 'package:sats_stack/shared/theme/app_theme.dart';

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
  Stream<String> chat(
    List<Map<String, String>> messages, {
    http.Client? client,
  }) async* {
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
    currency: 'USD',
    month: DateTime(2026, 3),
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

  // Audit A-15: an insight is about a month, so it goes stale when that is no
  // longer last month — not 30 days after it was made.
  group('staleness follows the month it covers', () {
    test('a March insight is current through April, stale in May', () async {
      final s = _Answers(db, 'You saved a quarter of your income.');
      await generate(s);
      expect(await s.cachedInsightMonth(), DateTime(2026, 3));
      expect(await s.isInsightStale(now: DateTime(2026, 4, 1)), isFalse);
      expect(await s.isInsightStale(now: DateTime(2026, 4, 30, 23)), isFalse);
      expect(await s.isInsightStale(now: DateTime(2026, 5, 1)), isTrue);
    });

    test('an insight saved before the month was stored', () async {
      // Made on 2 October, so about September: still showing on 1 November
      // was the bug, since that is under 30 days later.
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: AppConstants.settingMonthlyInsightDate,
              value: DateTime(2026, 10, 2, 10).toIso8601String(),
            ),
          );
      final s = _Answers(db, '');
      expect(await s.cachedInsightMonth(), DateTime(2026, 9));
      expect(await s.isInsightStale(now: DateTime(2026, 10, 31)), isFalse);
      expect(await s.isInsightStale(now: DateTime(2026, 11, 1, 9)), isTrue);
    });

    test('with nothing cached it is stale', () async {
      expect(await _Answers(db, '').isInsightStale(), isTrue);
    });
  });

  testWidgets('the card names the month its insight is about', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: AiInsightCard(
            aiEnabled: true,
            cachedInsight: 'Dining out doubled.',
            insightMonth: DateTime(2026, 9),
            offDeviceRecipient: 'Anthropic',
            onRefresh: () {},
          ),
        ),
      ),
    );
    expect(find.text('AI Insight · September 2026'), findsOneWidget);
  });
}
