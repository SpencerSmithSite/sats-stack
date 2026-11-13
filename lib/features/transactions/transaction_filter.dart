/// Searching and date-filtering the Transactions tab.
library;

import 'package:intl/intl.dart';

import '../../core/database/database.dart';
import '../../shared/utils/amount_input.dart';
import '../../shared/utils/date_range.dart';
import '../../shared/utils/fuzzy_match.dart';

/// The rows that answer a search: [exact] ones first, then the [close] ones
/// found only by tolerating a typo. Each keeps the order the rows came in.
typedef SearchResults = ({List<Transaction> exact, List<Transaction> close});

/// Every row's searchable text, folded and split once when the rows arrive
/// rather than on every search.
class TransactionSearch {
  TransactionSearch(this.rows)
    : _texts = [
        for (final tx in rows)
          SearchText(
            [tx.description, tx.category ?? '', tx.notes ?? ''].join('\n'),
          ),
      ];

  final List<Transaction> rows;
  final List<SearchText> _texts;

  /// The rows matching [query] that also pass [include]. An empty query
  /// matches every row, as exact.
  SearchResults search(String query, {bool Function(Transaction)? include}) {
    final q = SearchQuery(query);
    final amount = AmountQuery.parse(query);
    final exact = <Transaction>[];
    final close = <Transaction>[];
    for (var i = 0; i < rows.length; i++) {
      final tx = rows[i];
      if (include != null && !include(tx)) continue;
      if (amount != null) {
        // An amount is matched as one, or as typed: split into words, "12.50"
        // would find "#1250".
        if (amount.matches(tx) || _texts[i].folded.contains(q.folded)) {
          exact.add(tx);
        }
        continue;
      }
      switch (q.match(_texts[i])) {
        case MatchQuality.exact:
          exact.add(tx);
        case MatchQuality.close:
          close.add(tx);
        case MatchQuality.none:
          break;
      }
    }
    return (exact: exact, close: close);
  }
}

/// A search that reads as an amount — "12.50", "£12,50", "21000" — matched
/// against what each row shows: its fiat amount, or its sats.
class AmountQuery {
  const AmountQuery._(this.value, {required this.toTheCent});

  final double value;

  /// "12.50" means exactly that; "12" means anything from 12.00 to 12.99,
  /// since nobody types the cents of an amount they only half remember.
  final bool toTheCent;

  static final _shape = RegExp(r'^[-+]?[$£€]?\d[\d.,]*$');
  static final _cents = RegExp(r'[.,]\d{1,2}$');

  /// [text] as an amount, or null when it is not one.
  static AmountQuery? parse(String text) {
    final s = text.replaceAll(RegExp(r'\s'), '');
    if (!_shape.hasMatch(s)) return null;
    final digits = s.replaceFirst(RegExp(r'^[-+]?[$£€]?'), '');
    final value = parseUserAmount(digits);
    // Zero would match every fiat row, whose sats are 0.
    if (value == null || value == 0) return null;
    return AmountQuery._(
      value,
      toTheCent: value != value.truncateToDouble() || _cents.hasMatch(digits),
    );
  }

  bool matches(Transaction tx) {
    final fiat = tx.amountFiat.abs();
    if (toTheCent) return (fiat * 100).round() == (value * 100).round();
    return fiat.truncate() == value.truncate() ||
        tx.amountSats.abs() == value.truncate();
  }
}

/// The quick choices offered above the custom range in the filter sheet.
enum DatePreset {
  thisMonth('This month'),
  lastMonth('Last month'),
  last90Days('Last 90 days'),
  thisYear('This year');

  const DatePreset(this.label);

  final String label;

  /// The range this preset means on [today].
  DateRange rangeOn(DateTime today) => switch (this) {
    DatePreset.thisMonth => DateRange.month(today),
    // January's "last month" is DateTime(y, 0), which normalises to the
    // December before.
    DatePreset.lastMonth => DateRange.month(
      DateTime(today.year, today.month - 1),
    ),
    // Today and the 89 days before it.
    DatePreset.last90Days => DateRange.days(
      DateTime(today.year, today.month, today.day - 89),
      today,
    ),
    DatePreset.thisYear => DateRange.year(today),
  };

  /// The preset that means exactly [range] on [today], if any.
  static DatePreset? of(DateRange range, DateTime today) {
    for (final preset in values) {
      if (preset.rangeOn(today) == range) return preset;
    }
    return null;
  }
}

/// [range] as the filter chip shows it: a preset's name when it is one,
/// otherwise its first and last days.
String dateRangeLabel(DateRange range, DateTime today) {
  final preset = DatePreset.of(range, today);
  if (preset != null) return preset.label;
  final first = range.start;
  final last = range.lastDay;
  final full = DateFormat.yMMMd();
  if (first == last) return full.format(first);
  // The year once, at the end, when both days share it.
  final start =
      first.year == last.year
          ? DateFormat.MMMd().format(first)
          : full.format(first);
  return '$start – ${full.format(last)}';
}
