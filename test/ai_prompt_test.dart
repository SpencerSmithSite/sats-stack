/// What the AI is told: in the user's currency, for a named month, and each
/// question once.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/ollama_service.dart';
import 'package:sats_stack/features/ai_chat/ai_chat_screen.dart';

void main() {
  String prompt({
    double? btcPrice = 62234,
    String currency = 'GBP',
    DateTime? month,
  }) => OllamaService.composeSystemPrompt(
    totalStackSats: 20085,
    btcPrice: btcPrice,
    currency: currency,
    month: month ?? DateTime(2026, 10),
    monthlyIncome: 100,
    monthlySpending: 12.5,
    monthlySurplus: 87.5,
    spendingByCategory: const {'Food & Dining': 12.5},
    budgetChars: 4000,
    now: DateTime(2026, 10, 21),
  );

  group('the system prompt', () {
    test('is in the user\'s currency, not dollars', () {
      // Seen live: a GBP user's £12.50 coffee came back as "-$13".
      final p = prompt();
      expect(p, isNot(contains(r'$')));
      expect(p, isNot(contains('USD')));
      expect(p, contains('£12.50 GBP'));
      expect(p, contains('£62,234.00 GBP'));
    });

    test('gives the sats rate, so the model need not derive it', () {
      // 1e8 / 62,234 ≈ 1,607 sats per pound.
      expect(prompt(), contains('1 GBP = 1,607 sats'));
    });

    test('names the month and whether it is complete', () {
      expect(prompt(), contains('October 2026 (month to date)'));
      expect(
        prompt(month: DateTime(2026, 9)),
        contains('September 2026 (complete month)'),
      );
    });

    test('a missing price is said to be missing, not priced at zero', () {
      final p = prompt(btcPrice: null);
      expect(p, contains('BTC price: unavailable'));
      expect(p, isNot(contains('£0.00')));
      expect(prompt(btcPrice: 0), contains('BTC price: unavailable'));
    });
  });

  group('a chat turn', () {
    test('sends the new question once', () {
      final request = buildChatRequest(
        systemPrompt: 'system',
        history: const [
          (role: 'user', content: 'first question'),
          (role: 'assistant', content: 'first answer'),
        ],
        userMessage: 'second question',
        budgetChars: 4000,
      );
      expect(request.map((m) => m['content']), [
        'system',
        'first question',
        'first answer',
        'second question',
      ]);
    });

    test('drops the oldest turns first when the budget is tight', () {
      final request = buildChatRequest(
        systemPrompt: null,
        history: [
          (role: 'user', content: 'a' * 50),
          (role: 'assistant', content: 'b' * 50),
        ],
        userMessage: 'q',
        budgetChars: 60,
      );
      expect(request.map((m) => m['content']), ['b' * 50, 'q']);
    });
  });
}
