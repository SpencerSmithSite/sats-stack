import 'package:intl/intl.dart';

import 'date_range.dart';

/// The month a screen is showing, and the three questions every screen asks
/// about it: what comes before, what comes after, and is this the current one.
///
/// Dashboard, Analytics and Budgets each carried their own copy of
/// `DateTime(year, month ± 1)` and a byte-identical `_isCurrentMonth` getter.
/// Three copies of date arithmetic is three places for a month-boundary bug to
/// hide, which is exactly where the last one was found.
class MonthCursor {
  /// Normalises to the first of the month, so two cursors on the same month are
  /// equal whatever day they were built from.
  MonthCursor(DateTime month) : month = DateTime(month.year, month.month);

  /// The month containing [now], or today.
  factory MonthCursor.current([DateTime? now]) =>
      MonthCursor(now ?? DateTime.now());

  final DateTime month;

  MonthCursor get previous =>
      MonthCursor(DateTime(month.year, month.month - 1));

  /// December rolls over correctly: `DateTime(2026, 13)` normalises to
  /// January 2027.
  MonthCursor get next => MonthCursor(DateTime(month.year, month.month + 1));

  /// True when this is the month we are living in. Screens use it to decide
  /// whether the "next month" arrow is enabled — there is nothing to show in
  /// the future.
  bool isCurrent([DateTime? now]) {
    final today = now ?? DateTime.now();
    return month.year == today.year && month.month == today.month;
  }

  /// The half-open range this month covers, for aggregates.
  DateRange get range => DateRange.month(month);

  /// How the month is written in an app bar: "March 2026".
  String get label => DateFormat('MMMM yyyy').format(month);

  @override
  bool operator ==(Object other) =>
      other is MonthCursor && other.month == month;

  @override
  int get hashCode => month.hashCode;

  @override
  String toString() => 'MonthCursor($label)';
}
