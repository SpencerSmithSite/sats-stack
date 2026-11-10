/// No amounts in a notification (audit P-8).
///
/// Bodies said "You've stacked 21,000,000 sats ≈ $16,800,000" and gave
/// budgets and overspends in money, readable on a locked or shared screen —
/// for Bitcoin holdings, a physical-security risk.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/services/notification_service.dart';

void main() {
  late List<String> sent;
  late NotificationService notifications;
  setUp(() {
    sent = [];
    notifications = NotificationService(
      deliver: (id, title, body) async {
        sent.add('$title\n$body');
        return true;
      },
    );
  });

  /// Any figure but a percentage: money, sats, or a count of either.
  final amount = RegExp(r'[$€£₿]|\bsats?\b|\d[\d,.]*(?!\d*%)\b');

  test('the stack goal says it was reached, not how much', () async {
    await notifications.showStackGoalReached(goalSats: 21000000);
    expect(sent.single, contains('stack goal'));
    expect(sent.single, isNot(matches(amount)));
  });

  test('budget alerts name the category, and only a percentage', () async {
    await notifications.showBudgetWarning(
      categoryId: 1,
      categoryName: 'Food & Dining',
      percentUsed: 85,
      month: DateTime(2026, 3),
    );
    await notifications.showBudgetOverspend(
      categoryId: 1,
      categoryName: 'Food & Dining',
      month: DateTime(2026, 3),
    );
    expect(sent, hasLength(2));
    expect(sent[0], contains('85%'));
    for (final text in sent) {
      expect(text, contains('Food & Dining'));
      expect(text.replaceAll('85%', ''), isNot(matches(amount)), reason: text);
    }
  });
}
