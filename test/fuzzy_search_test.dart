/// Search forgives typos and abbreviations, and the date filter keeps whole
/// days.
///
/// Search matched exact substrings only, so "starbuks" found nothing, and
/// there was no way to narrow the list to a stretch of dates.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:sats_stack/core/database/database.dart';
import 'package:sats_stack/features/transactions/transaction_filter.dart';
import 'package:sats_stack/shared/utils/date_range.dart';
import 'package:sats_stack/shared/utils/fuzzy_match.dart';

MatchQuality match(String query, String text) =>
    SearchQuery(query).match(SearchText(text));

var _nextId = 0;

Transaction row(
  String description, {
  double fiat = -1,
  int sats = 0,
  String? category,
  String? notes,
}) => Transaction(
  id: _nextId++,
  walletId: 1,
  date: DateTime(2026, 11, 1),
  description: description,
  amountSats: sats,
  amountFiat: fiat,
  fiatCurrency: 'USD',
  category: category,
  notes: notes,
  source: 'manual',
  isBitcoin: sats != 0,
  dedupHash: '$_nextId',
  createdAt: DateTime(2026, 11, 1),
  isOwnTransfer: false,
);

void main() {
  group('matching', () {
    test('a typo still finds the merchant', () {
      expect(match('starbuks', 'STARBUCKS #1234'), MatchQuality.close);
      expect(match('cofee', 'Coffee'), MatchQuality.close);
      expect(match('netlfix', 'Netflix.com'), MatchQuality.close);
      expect(match('amazn', 'Amazon'), MatchQuality.close);
    });

    test('partial words and any word order are exact', () {
      expect(match('amzn mktp', 'AMZN Mktp US'), MatchQuality.exact);
      expect(match('mktp amzn', 'AMZN Mktp US'), MatchQuality.exact);
      expect(match('starbu', 'STARBUCKS #1234'), MatchQuality.exact);
      expect(match('#1234', 'STARBUCKS #1234'), MatchQuality.exact);
    });

    test('a half-typed word with a typo matches the start of the word', () {
      expect(match('strabuc', 'STARBUCKS #1234'), MatchQuality.close);
    });

    test('a vowel-less abbreviation matches the word it shortens', () {
      expect(match('amzn', 'Amazon.co.uk'), MatchQuality.close);
      expect(match('wmt', 'Walmart Supercenter'), MatchQuality.close);
      // Same letters, different first letter: not an abbreviation of it.
      expect(match('wmt', 'Tesco Metro'), MatchQuality.none);
    });

    test('case and accents are ignored', () {
      expect(match('cafe nero', 'CAFÉ NÉRO'), MatchQuality.exact);
      expect(match('café', 'Cafe Rouge'), MatchQuality.exact);
      expect(match('strasse', 'Hauptstraße 4'), MatchQuality.exact);
      expect(foldForSearch('Ærø Ñandú'), 'aero nandu');
    });

    test('short queries only match what they contain', () {
      // Two letters: a typo allowance would match nearly every row.
      expect(match('re', 'Rent'), MatchQuality.exact);
      expect(match('rn', 'Rent'), MatchQuality.none);
      expect(match('xe', 'Coffee'), MatchQuality.none);
      // Three letters with a vowel are not an abbreviation, and too short
      // for a typo.
      expect(match('cfo', 'Coffee'), MatchQuality.none);
      expect(match('caf', 'Coffee'), MatchQuality.none);
    });

    test('unrelated text is not matched', () {
      for (final text in [
        'Shell Oil 5543',
        'Rent payment',
        'Netflix.com',
        'Council tax',
        'Salary ACME Ltd',
      ]) {
        expect(match('starbuks', text), MatchQuality.none, reason: text);
        expect(match('coffee', text), MatchQuality.none, reason: text);
        expect(match('groceries', text), MatchQuality.none, reason: text);
      }
      // The first letter has to be right.
      expect(match('bent', 'Rent'), MatchQuality.none);
    });

    test('numbers are never fuzzed', () {
      expect(match('1235', 'STARBUCKS #1234'), MatchQuality.none);
      expect(match('starbucks 1235', 'STARBUCKS #1234'), MatchQuality.none);
      expect(match('starbuks 1234', 'STARBUCKS #1234'), MatchQuality.close);
    });

    test('every word of the query has to match', () {
      expect(match('starbuks rent', 'STARBUCKS #1234'), MatchQuality.none);
    });

    test('an empty query matches everything', () {
      expect(match('', 'anything'), MatchQuality.exact);
      expect(match('   ', 'anything'), MatchQuality.exact);
    });

    test('edit distance counts a swap of neighbours as one edit', () {
      expect(prefixEditDistance('rnet', 'rent', 2), 1);
      expect(prefixEditDistance('starbuks', 'starbucks', 2), 1);
      // Against the start of the word, not all of it.
      expect(prefixEditDistance('starbuc', 'starbucks', 1), 0);
      expect(prefixEditDistance('strabuc', 'starbucks', 1), 1);
      // Past the limit it stops counting.
      expect(prefixEditDistance('abcd', 'wxyz', 1), 2);
      expect(prefixEditDistance('abcdefgh', 'ab', 2), 3);
    });
  });

  group('searching rows', () {
    test('exact matches come first, then close ones', () {
      final typo = row('Starbuks Reserve');
      final exact = row('STARBUCKS #1234');
      final other = row('Rent');
      final results = TransactionSearch([
        typo,
        exact,
        other,
      ]).search('starbucks');
      expect(results.exact, [exact]);
      expect(results.close, [typo]);
    });

    test('category and notes are searched too', () {
      final byCategory = row('TFL', category: 'Transport');
      final byNote = row('Transfer', notes: 'birthday present for Sam');
      final search = TransactionSearch([byCategory, byNote]);
      expect(search.search('transprt').close, [byCategory]);
      expect(search.search('birthday').exact, [byNote]);
    });

    test('rows filtered out are not searched', () {
      final a = row('Coffee');
      final b = row('Coffee beans');
      final results = TransactionSearch([
        a,
        b,
      ]).search('coffee', include: (tx) => tx != a);
      expect(results.exact, [b]);
    });

    test('an empty query keeps every row, in order', () {
      final rows = [row('a'), row('b'), row('c')];
      final results = TransactionSearch(rows).search('');
      expect(results.exact, rows);
      expect(results.close, isEmpty);
    });

    test('an amount finds the rows of that amount', () {
      final lunch = row('Lunch', fiat: -12.5);
      final twelve = row('Book', fiat: -12);
      final cents = row('Snack', fiat: -12.99);
      final big = row('Desk', fiat: -125);
      final stack = row('DCA', fiat: 0, sats: 21000);
      final search = TransactionSearch([lunch, twelve, cents, big, stack]);

      expect(search.search('12.50').exact, [lunch]);
      expect(search.search(r'$12.50').exact, [lunch]);
      expect(search.search('12,50').exact, [lunch]);
      // No cents: any amount in that whole unit.
      expect(search.search('12').exact, [lunch, twelve, cents]);
      expect(search.search('21,000').exact, [stack]);
      expect(search.search('21000').exact, [stack]);
    });

    test('zero and words are not amounts', () {
      expect(AmountQuery.parse('0'), isNull);
      expect(AmountQuery.parse('0.00'), isNull);
      expect(AmountQuery.parse('coffee'), isNull);
      expect(AmountQuery.parse('12 coffee'), isNull);
      expect(AmountQuery.parse('£4.50')?.value, 4.5);
    });
  });

  group('whole-day ranges', () {
    final range = DateRange.days(DateTime(2026, 11, 3), DateTime(2026, 11, 5));

    test('the first and last instants of the picked days are in', () {
      expect(range.contains(DateTime(2026, 11, 3)), isTrue);
      expect(range.contains(DateTime(2026, 11, 5, 12)), isTrue);
      expect(range.contains(DateTime(2026, 11, 5, 23, 59, 59, 999)), isTrue);
      expect(
        range.contains(DateTime(2026, 11, 5, 23, 59, 59, 999, 999)),
        isTrue,
      );
    });

    test('the instants either side are out', () {
      expect(range.contains(DateTime(2026, 11, 6)), isFalse);
      expect(range.contains(DateTime(2026, 11, 2, 23, 59, 59, 999)), isFalse);
    });

    test('a time on the picked days is ignored', () {
      expect(
        DateRange.days(DateTime(2026, 11, 3, 15), DateTime(2026, 11, 5, 9)),
        range,
      );
    });

    test('one day, at a month end and a year end', () {
      final jan31 = DateRange.days(
        DateTime(2026, 1, 31),
        DateTime(2026, 1, 31),
      );
      expect(jan31.end, DateTime(2026, 2, 1));
      expect(jan31.contains(DateTime(2026, 1, 31, 23, 59, 59, 999)), isTrue);
      expect(jan31.contains(DateTime(2026, 2, 1)), isFalse);

      final dec31 = DateRange.days(
        DateTime(2026, 12, 31),
        DateTime(2026, 12, 31),
      );
      expect(dec31.end, DateTime(2027, 1, 1));

      expect(
        DateRange.days(DateTime(2028, 2, 29), DateTime(2028, 2, 29)).end,
        DateTime(2028, 3, 1),
      );
    });

    test('the last day reads back as the day picked', () {
      expect(range.lastDay, DateTime(2026, 11, 5));
      expect(DateRange.month(DateTime(2026, 2)).lastDay, DateTime(2026, 2, 28));
    });
  });

  group('presets', () {
    // Mid-January, so last month and the last 90 days cross a year.
    final today = DateTime(2026, 1, 15, 13, 30);

    test('each preset is a half-open range of whole days', () {
      expect(
        DatePreset.thisMonth.rangeOn(today),
        DateRange(DateTime(2026, 1, 1), DateTime(2026, 2, 1)),
      );
      expect(
        DatePreset.lastMonth.rangeOn(today),
        DateRange(DateTime(2025, 12, 1), DateTime(2026, 1, 1)),
      );
      expect(
        DatePreset.last90Days.rangeOn(today),
        DateRange(DateTime(2025, 10, 18), DateTime(2026, 1, 16)),
      );
      expect(
        DatePreset.thisYear.rangeOn(today),
        DateRange(DateTime(2026, 1, 1), DateTime(2027, 1, 1)),
      );
    });

    test('the last 90 days are 90 days, today included', () {
      final range = DatePreset.last90Days.rangeOn(today);
      var days = 0;
      for (var d = range.start; d.isBefore(range.end); days++) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      expect(days, 90);
      expect(range.contains(DateTime(2026, 1, 15, 23, 59, 59, 999)), isTrue);
    });

    test('last month includes its final instant', () {
      final range = DatePreset.lastMonth.rangeOn(today);
      expect(range.contains(DateTime(2025, 12, 31, 23, 59, 59, 999)), isTrue);
      expect(range.contains(DateTime(2026, 1, 1)), isFalse);
    });

    test('a range is labelled by its preset, or by its days', () {
      expect(
        dateRangeLabel(DatePreset.lastMonth.rangeOn(today), today),
        'Last month',
      );
      expect(DatePreset.of(nov(3, 5), today), isNull);
      expect(dateRangeLabel(nov(3, 5), today), 'Nov 3 – Nov 5, 2025');
      expect(dateRangeLabel(nov(3, 3), today), 'Nov 3, 2025');
      expect(
        dateRangeLabel(
          DateRange.days(DateTime(2025, 12, 30), DateTime(2026, 1, 2)),
          today,
        ),
        'Dec 30, 2025 – Jan 2, 2026',
      );
    });
  });
}

DateRange nov(int firstDay, int lastDay) =>
    DateRange.days(DateTime(2025, 11, firstDay), DateTime(2025, 11, lastDay));
